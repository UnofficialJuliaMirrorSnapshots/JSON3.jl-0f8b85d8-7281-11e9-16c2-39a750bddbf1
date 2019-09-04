defaultminimum(::Union{Nothing, Missing}) = 4
defaultminimum(::Number) = 20
defaultminimum(::T) where {T <: Base.IEEEFloat} = Parsers.neededdigits(T)
defaultminimum(x::Bool) = ifelse(x, 4, 5)
defaultminimum(x::AbstractString) = ncodeunits(x) + 2
defaultminimum(x::Symbol) = ccall(:strlen, Csize_t, (Cstring,), x) + 2
defaultminimum(x::Enum) = 16
defaultminimum(::Type{T}) where {T} = 16
defaultminimum(x::Char) = 3
defaultminimum(x::Union{Tuple, AbstractSet, AbstractArray}) = isempty(x) ? 2 : sum(defaultminimum, x)
defaultminimum(x::Union{AbstractDict, NamedTuple, Pair}) = isempty(x) ? 2 : sum(defaultminimum(k) + defaultminimum(v) for (k, v) in keyvaluepairs(x))
defaultminimum(x) = max(2, sizeof(x))

function write(io::IO, obj::T) where {T}
    len = defaultminimum(obj)
    buf = Base.StringVector(len)
    buf, pos, len = write(StructType(obj), buf, 1, length(buf), obj)
    return Base.write(io, resize!(buf, pos - 1))
end

function write(obj::T) where {T}
    len = defaultminimum(obj)
    buf = Base.StringVector(len)
    buf, pos, len = write(StructType(obj), buf, 1, length(buf), obj)
    return String(resize!(buf, pos - 1))
end

_getfield(x, i) = isdefined(x, i) ? Core.getfield(x, i) : nothing
_isempty(x, i) = !isdefined(x, i) || _isempty(getfield(x, i))
_isempty(x::Union{Object, Array, AbstractDict, AbstractArray, AbstractString, Tuple, NamedTuple}) = isempty(x)
_isempty(::Number) = false
_isempty(::Nothing) = true
_isempty(x) = false

@noinline function realloc!(buf, len, n)
    # println("re-allocing...")
    new = zeros(UInt8, max(n, trunc(Int, len * 1.25)))
    copyto!(new, 1, buf, 1, len)
    return new, length(new)
end

macro check(n)
    esc(quote
        if (pos + $n - 1) > len
            buf, len = realloc!(buf, len, pos + $n - 1)
        end
    end)
end

macro writechar(chars...)
    block = quote
        @boundscheck @check($(length(chars)))
    end
    for c in chars
        push!(block.args, quote
            @inbounds buf[pos] = UInt8($c)
            pos += 1
        end)
    end
    #println(macroexpand(@__MODULE__, block))
    return esc(block)
end

# we need to special-case writing Type{T} because of ambiguities w/ StructTypes
write(::Struct, buf, pos, len, ::Type{T}) where {T} = write(StringType(), buf, pos, len, Base.string(T))
write(::Mutable, buf, pos, len, ::Type{T}) where {T} = write(StringType(), buf, pos, len, Base.string(T))
write(::ObjectType, buf, pos, len, ::Type{T}) where {T} = write(StringType(), buf, pos, len, Base.string(T))
write(::ArrayType, buf, pos, len, ::Type{T}) where {T} = write(StringType(), buf, pos, len, Base.string(T))
write(::StringType, buf, pos, len, ::Type{T}) where {T} = write(StringType(), buf, pos, len, Base.string(T))
write(::NumberType, buf, pos, len, ::Type{T}) where {T} = write(StringType(), buf, pos, len, Base.string(T))
write(::NullType, buf, pos, len, ::Type{T}) where {T} = write(StringType(), buf, pos, len, Base.string(T))
write(::BoolType, buf, pos, len, ::Type{T}) where {T} = write(StringType(), buf, pos, len, Base.string(T))
write(::AbstractType, buf, pos, len, ::Type{T}) where {T} = write(StringType(), buf, pos, len, Base.string(T))
write(::NoStructType, buf, pos, len, ::Type{T}) where {T} = write(StringType(), buf, pos, len, Base.string(T))

write(::NoStructType, buf, pos, len, ::T) where {T} = throw(ArgumentError("$T doesn't have a defined `JSON3.StructType`"))

# generic object writing
@inline function write(::Union{Struct, Mutable}, buf, pos, len, x::T) where {T}
    @writechar '{'
    N = fieldcount(T)
    N == 0 && @goto done
    excl = excludes(T)
    nms = names(T)
    emp = omitempties(T)
    afterfirst = false
    Base.@nexprs 32 i -> begin
        k_i = fieldname(T, i)
        if !symbolin(excl, k_i) && (!symbolin(emp, k_i) || !_isempty(x, i))
            afterfirst && @writechar ','
            afterfirst = true
            buf, pos, len = write(StringType(), buf, pos, len, jsonname(nms, k_i))
            @writechar ':'
            y = _getfield(x, i)
            buf, pos, len = write(StructType(y), buf, pos, len, y)
        end
        N == i && @goto done
    end
    if N > 32
        for i = 33:N
            k_i = fieldname(T, i)
            if !symbolin(excl, k_i) && (!symbolin(emp, k_i) || !_isempty(x, i))
                @writechar ','
                buf, pos, len = write(StringType(), buf, pos, len, jsonname(nms, k_i))
                @writechar ':'
                y = _getfield(x, i)
                buf, pos, len = write(StructType(y), buf, pos, len, y)
            end
        end
    end

@label done
    @writechar '}'
    return buf, pos, len
end

function write(::ObjectType, buf, pos, len, x::T) where {T}
    @writechar '{'
    pairs = keyvaluepairs(x)
    n = length(pairs)
    i = 1
    for (k, v) in pairs
        buf, pos, len = write(StringType(), buf, pos, len, Base.string(k))
        @writechar ':'
        buf, pos, len = write(StructType(v), buf, pos, len, v)
        if i < n
            @writechar ','
        end
        i += 1
    end

@label done
    @writechar '}'
    return buf, pos, len
end

function write(::ArrayType, buf, pos, len, x::T) where {T}
    @writechar '['
    n = length(x)
    i = 1
    for y in x
        buf, pos, len = write(StructType(y), buf, pos, len, y)
        if i < n
            @writechar ','
        end
        i += 1
    end
    @writechar ']'
    return buf, pos, len
end

function write(::NullType, buf, pos, len, x)
    @writechar 'n' 'u' 'l' 'l'
    return buf, pos, len
end

write(::BoolType, buf, pos, len, x) = write(BoolType(), buf, pos, len, Bool(x))
function write(::BoolType, buf, pos, len, x::Bool)
    if x
        @writechar 't' 'r' 'u' 'e'
    else
        @writechar 'f' 'a' 'l' 's' 'e'
    end
    return buf, pos, len
end

# adapted from base/intfuncs.jl
function write(::NumberType, buf, pos, len, y::Integer)
    x, neg = Base.split_sign(y)
    if neg
        @inbounds @writechar UInt8('-')
    end
    n = i = ndigits(x, base=10, pad=1)
    @check i
    while i > 0
        @inbounds buf[pos + i - 1] = 48 + rem(x, 10)
        x = oftype(x, div(x, 10))
        i -= 1
    end
    return buf, pos + n, len
end

write(::NumberType, buf, pos, len, x::T) where {T} = write(NumberType(), buf, pos, len, numbertype(T)(x))
function write(::NumberType, buf, pos, len, x::AbstractFloat)
    if !isfinite(x)
        @writechar 'n' 'u' 'l' 'l'
        return buf, pos, len
    end
    bytes = codeunits(Base.string(x))
    sz = sizeof(bytes)
    @check sz
    for i = 1:sz
        @inbounds @writechar bytes[i]
    end

    return buf, pos, len
end

@inline function write(::NumberType, buf, pos, len, x::T) where {T <: Base.IEEEFloat}
    if !isfinite(x)
        @writechar 'n' 'u' 'l' 'l'
        return buf, pos, len
    end
    @check Parsers.neededdigits(T)
    pos = Parsers.writeshortest(buf, pos, x)
    return buf, pos, len
end

const NEEDESCAPE = Set(map(UInt8, ('"', '\\', '\b', '\f', '\n', '\r', '\t')))

function escapechar(b)
    b == UInt8('"')  && return UInt8('"')
    b == UInt8('\\') && return UInt8('\\')
    b == UInt8('\b') && return UInt8('b')
    b == UInt8('\f') && return UInt8('f')
    b == UInt8('\n') && return UInt8('n')
    b == UInt8('\r') && return UInt8('r')
    b == UInt8('\t') && return UInt8('t')
    return 0x00
end

iscntrl(c::Char) = c <= '\x1f' || '\x7f' <= c <= '\u9f'
function escaped(b)
    if b == UInt8('/')
        return [UInt8('/')]
    elseif b >= 0x80
        return [b]
    elseif b in NEEDESCAPE
        return [UInt8('\\'), escapechar(b)]
    elseif iscntrl(Char(b))
        return UInt8[UInt8('\\'), UInt8('u'), Base.string(b, base=16, pad=4)...]
    else
        return [b]
    end
end

const ESCAPECHARS = [escaped(b) for b = 0x00:0xff]
const ESCAPELENS = [length(x) for x in ESCAPECHARS]

function escapelength(str)
    x = 0
    @simd for i = 1:ncodeunits(str)
        @inbounds len = ESCAPELENS[codeunit(str, i) + 0x01]
        x += len
    end
    return x
end

write(::StringType, buf, pos, len, x) = write(StringType(), buf, pos, len, Base.string(x))
function write(::StringType, buf, pos, len, x::AbstractString)
    sz = ncodeunits(x)
    el = escapelength(x)
    @check (el + 2)
    @inbounds @writechar '"'
    if el > sz
        for i = 1:sz
            @inbounds escbytes = ESCAPECHARS[codeunit(x, i) + 0x01]
            for j = 1:length(escbytes)
                @inbounds buf[pos] = escbytes[j]
                pos += 1
            end
        end
    else
        @simd for i = 1:sz
            @inbounds buf[pos] = codeunit(x, i)
            pos += 1
        end
    end
    @inbounds @writechar '"'
    return buf, pos, len
end

function write(::StringType, buf, pos, len, x::Symbol)
    ptr = Base.unsafe_convert(Ptr{UInt8}, x)
    slen = ccall(:strlen, Csize_t, (Cstring,), ptr)
    @check (slen + 2)
    @inbounds @writechar '"'
    for i = 1:slen
        @inbounds @writechar unsafe_load(ptr, i)
    end
    @inbounds @writechar '"'
    return buf, pos, len
end
