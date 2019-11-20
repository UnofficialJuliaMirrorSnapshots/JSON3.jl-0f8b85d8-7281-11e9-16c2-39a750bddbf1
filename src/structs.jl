abstract type StructType end

"Default `JSON3.StructType` for types that don't have a `StructType` defined; this ensures any object going in/out of JSON3 has an explicit `StructType`"
struct NoStructType <: StructType end

# "Data" type: fields are json keys, field values are json values; use names, omitempties, excludes
abstract type DataType <: StructType end

"""
    JSON3.StructType(::Type{MyType}) = JSON3.Struct()

This `StructType` is less flexible, yet more performant than `JSON3.Mutable`. For reading a `JSON3.Struct()` from a JSON string input, each key-value pair is read in the order it is encountered in the JSON input, the keys are ignored, and the values are directly passed to the type at the end of the object parsing like `MyType(val1, val2, val3)`. Yes, the JSON specification says that Objects are specifically ***un-ordered*** collections of key-value pairs, but the truth is that many JSON libraries provide ways to maintain JSON Object key-value pair order when reading/writing. Because of the minimal processing done while parsing, and the "trusting" that the Julia type constructor will be able to handle fields being present, missing, or even extra fields that should be ignored, this is the fastest possible method for mapping a JSON input to a Julia structure. If your workflow interacts with non-Julia APIs for sending/receiving JSON, you should take care to test and confirm the use of `JSON3.Struct()` in the cases mentioned above: what if a field is missing when parsing? what if the key-value pairs are out of order? what if there extra fields get included that weren't anticipated? If your workflow is questionable on these points, or it would be too difficult to account for these scenarios in your type constructor, it would be better to consider the `JSON3.Mutable()` option.
"""
struct Struct <: DataType end

"""
    JSON3.StructType(::Type{MyType}) = JSON3.Mutable()

The slightly less performant, yet much more robust method for directly mapping Julia struct fields to JSON objects is via `JSON3.Mutable()`. This technique requires your Julia type to be defined, ***at a minimum***, like:
```julia
mutable struct MyType
    field1
    field2
    field3
    # etc.

    MyType() = new()
end
```
Note specifically that we're defining a `mutable struct` to allow field mutation, and providing a `MyType() = new()` inner constructor which constructs an "empty" `MyType` where isbits fields will be randomly initialized, and reference fields will be `#undef`. (Note that the inner constructor doesn't need to be ***exactly*** this, but at least needs to be callable like `MyType()`. If certain fields need to be intialized or zeroed out for security, then this should be accounted for in the inner constructor). For these mutable types, the type will first be initizlied like `MyType()`, then JSON parsing will parse each key-value pair in a JSON object, setting the field as the key is encountered, and converting the JSON value to the appropriate field value. This flow has the nice properties of: allowing parsing success even if fields are missing in the JSON structure, and if "extra" fields exist in the JSON structure that aren't apart of the Julia struct's fields, it will automatically be ignored. This allows for maximum robustness when mapping Julia types to arbitrary JSON objects that may be generated via web services, other language JSON libraries, etc.

There are a few additional helper methods that can be utilized by `JSON3.Mutable()` types to hand-tune field reading/writing behavior:

* `JSON3.names(::Type{MyType}) = ((:field1, :json1), (:field2, :json2))`: provides a mapping of Julia field name to expected JSON object key name. This affects both reading and writing. When reading the `json1` key, the `field1` field of `MyType` will be set. When writing the `field2` field of `MyType`, the JSON key will be `json2`.
* `JSON3.excludes(::Type{MyType}) = (:field1, :field2)`: specify fields of `MyType` to ignore when reading and writing, provided as a `Tuple` of `Symbol`s. When reading, if `field1` is encountered as a JSON key, it's value will be read, but the field will not be set in `MyType`. When writing, `field1` will be skipped when writing out `MyType` fields as key-value pairs.
* `JSON3.omitempties(::Type{MyType}) = (:field1, :field2)`: specify fields of `MyType` that shouldn't be written if they are "empty", provided as a `Tuple` of `Symbol`s. This only affects writing. If a field is a collection (AbstractDict, AbstractArray, etc.) and `isempty(x) === true`, then it will not be written. If a field is `#undef`, it will not be written. If a field is `nothing`, it will not be written.
"""
struct Mutable <: DataType end

StructType(u::Union) = Struct()
StructType(::Type{Any}) = Struct()
StructType(::Type{T}) where {T} = NoStructType()
StructType(x::T) where {T} = StructType(T)

"""
    JSON3.names(::Type{MyType}) = ((:field1, :json1), (:field2, :json2))

Provides a mapping of Julia field name to expected JSON object key name.
This affects both reading and writing.
When reading the `json1` key, the `field1` field of `MyType` will be set.
When writing the `field2` field of `MyType`, the JSON key will be `json2`.
"""
function names end

# maps Julia struct field name to json key name: ((:field1, :json1), (:field2, :json2))
names(x::T) where {T} = names(T)
names(::Type{T}) where {T} = ()

Base.@pure function julianame(names::Tuple{Vararg{Tuple{Symbol, Symbol}}}, jsonname::Symbol)
    for nm in names
        nm[2] === jsonname && return nm[1]
    end
    return jsonname
end

Base.@pure function jsonname(names::Tuple{Vararg{Tuple{Symbol, Symbol}}}, julianame::Symbol)
    for nm in names
        nm[1] === julianame && return nm[2]
    end
    return julianame
end

"""
    JSON3.excludes(::Type{MyType}) = (:field1, :field2)

Specify for a `JSON3.Mutable` `StructType` the fields, given as a `Tuple` of `Symbol`s, that should be ignored when reading, and excluded from writing.
"""
function excludes end
# Julia struct field names as symbols that will be ignored when reading, and never written
excludes(x::T) where {T} = excludes(T)
excludes(::Type{T}) where {T} = ()

"""
    JSON3.omitempties(::Type{MyType}) = (:field1, :field2)

Specify for a `JSON3.Mutable` `StructType` the fields, given as a `Tuple` of `Symbol`s, that should not be written if they're considered "empty".
If a field is a collection (AbstractDict, AbstractArray, etc.) and `isempty(x) === true`, then it will not be written. If a field is `#undef`, it will not be written. If a field is `nothing`, it will not be written.
"""
function omitempties end

# Julia struct field names as symbols
omitempties(x::T) where {T} = omitempties(T)
omitempties(::Type{T}) where {T} = ()

"""
    JSON3.keywordargs(::Type{MyType}) = (field1=(dateformat=dateformat"mm/dd/yyyy",), field2=(dateformat=dateformat"HH MM SS",))

Specify for a `JSON3.Mutable` `StructType` the keyword arguments by field, given as a `NamedTuple` of `NamedTuple`s, that should be passed
to the `JSON3.construct` method when deserializing `MyType`. This essentially allows defining specific keyword arguments you'd like to be passed for each field
in your struct. Note that keyword arguments can be passed when reading, like `JSON3.read(source, MyType; dateformat=...)` and they will be passed down to each `JSON3.construct` method.
`JSON3.keywordargs` just allows the defining of specific keyword arguments per field.
"""
function keywordargs end

keywordargs(x::T) where {T} = keywordargs(T)
keywordargs(::Type{T}) where {T} = NamedTuple()

"""
    JSON3.JSONType

An abstract type used in the API for "interface types" to map Julia types to a specific JSON type. See docs for the following for more details:

    * JSON3.ObjectType
    * JSON3.ArrayType
    * JSON3.StringType
    * JSON3.NumberType
    * JSON3.BoolType
    * JSON3.NullType
"""
abstract type JSONType end

"""
    JSON3.StructType(::Type{MyType}) = JSON3.ObjectType()

Declaring my type is `JSON3.ObjectType()` means it should map to a JSON object of unordered key-value pairs, where keys are `Symbol` or `String`, and values are any other type (or `Any`).

Types already declared as `JSON3.ObjectType()` include:
  * Any subtype of `AbstractDict`
  * Any `NamedTuple` type
  * Any `Pair` type

So if your type subtypes `AbstractDict` and implements its interface, then JSON reading/writing should just work!

Otherwise, the interface to satisfy `JSON3.ObjectType()` for reading is:

  * `MyType(x::Dict{Symbol, Any})`: implement a constructor that takes a `Dict{Symbol, Any}` of key-value pairs parsed from JSON
  * `JSON3.construct(::Type{MyType}, x::Dict; kw...)`: alternatively, you may overload the `JSON3.construct` method for your type if defining a constructor is undesirable (or would cause other clashes or ambiguities)

The interface to satisfy for writing is:

  * `pairs(x)`: implement the `pairs` iteration function (from Base) to iterate key-value pairs to be written out to JSON
  * `JSON3.keyvaluepairs(x::MyType)`: alternatively, you can overload the `JSON3.keyvaluepairs` function if overloading `pairs` isn't possible for whatever reason
"""
struct ObjectType <: JSONType end

"""
    JSON3.StructType(::Type{MyType}) = JSON3.ArrayType()

Declaring my type is `JSON3.ArrayType()` means it should map to a JSON array of ordered elements, homogenous or otherwise.

Types already declared as `JSON3.ArrayType()` include:
  * Any subtype of `AbstractArray`
  * Any subtype of `AbstractSet`
  * Any `Tuple` type

So if your type already subtypes these and satifies the interface, things should just work.

Otherwise, the interface to satisfy `JSON3.ArrayType()` for reading is:

  * `MyType(x::Vector)`: implement a constructo that takes a `Vector` argument of values and constructs a `MyType`
  * `JSON3.construct(::Type{MyType}, x::Vector; kw...)`: alternatively, you may overload the `JSON3.construct` method for your type if defining a constructor isn't possible
  * Optional: `Base.IteratorEltype(::Type{MyType})` and `Base.eltype(x::MyType)`: this can be used to signal to JSON3 that elements for your type are expected to be a single type and JSON3 will attempt to parse as such

The interface to satisfy for writing is:

  * `iterate(x::MyType)`: just iteration over each element is required; note if you subtype `AbstractArray` and define `getindex(x::MyType, i::Int)`, then iteration is already defined for your type
"""
struct ArrayType <: JSONType end

"""
    JSON3.StructType(::Type{MyType}) = JSON3.StringType()

Declaring my type is `JSON3.StringType()` means it should map to a JSON string value.

Types already declared as `JSON3.StringType()` include:
  * Any subtype of `AbstractString`
  * The `Symbol` type
  * Any subtype of `Enum` (values are written with their symbolic name)
  * The `Char` type

So if your type is an `AbstractString` or `Enum`, then things should already work.

Otherwise, the interface to satisfy `JSON3.StringType()` for reading is:

  * `MyType(x::String)`: define a constructor for your type that takes a single String argument
  * `JSON3.construct(::Type{MyType}, x::String; kw...)`: alternatively, you may overload `JSON3.construct` for your type
  * `JSON3.construct(::Type{MyType}, ptr::Ptr{UInt8}, len::Int; kw...)`: another option is to overload `JSON3.construct` with pointer and length arguments, if it's possible for your custom type to take advantage of avoiding the full string materialization; note that your type should implement both `JSON3.construct` methods, since JSON strings with escape characters in them will be fully unescaped before calling `JSON3.construct(::Type{MyType}, x::String)`, i.e. there is no direct pointer/length method for escaped strings

The interface to satisfy for writing is:

  * `Base.string(x::MyType)`: overload `Base.string` for your type to return a "stringified" value
"""
struct StringType <: JSONType end

"""
    JSON3.StructType(::Type{MyType}) = JSON3.NumberType()

Declaring my type is `JSON3.NumberType()` means it should map to a JSON number value.

Types already declared as `JSON3.NumberType()` include:
  * Any subtype of `Signed`
  * Any subtype of `Unsigned`
  * Any subtype of `AbstractFloat`

In addition to declaring `JSON3.NumberType()`, custom types can also specify a specific, ***existing*** number type it should map to. It does this like:
```julia
JSON3.numbertype(::Type{MyType}) = Float64
```

In this case, I'm declaring the `MyType` should map to an already-supported number type `Float64`. This means that when reading, JSON3 will first parse a `Float64` value, and then call `MyType(x::Float64)`. Note that custom types may also overload `JSON3.construct(::Type{MyType}, x::Float64)` if using a constructor isn't possible. Also note that the default for any type declared as `JSON3.NumberType()` is `Float64`.

Similarly for writing, JSON3 will first call `Float64(x::MyType)` before writing the resulting `Float64` value out as a JSON number.
"""
struct NumberType <: JSONType end

"""
    JSON3.StructType(::Type{MyType}) = JSON3.BoolType()

Declaring my type is `JSON3.BoolType()` means it should map to a JSON boolean value.

Types already declared as `JSON3.BoolType()` include:
  * `Bool`

The interface to satisfy for reading is:
  * `MyType(x::Bool)`: define a constructor that takes a single `Bool` value
  * `JSON3.construct(::Type{MyType}, x::Bool; kw...)`: alternatively, you may overload `JSON3.construct`

The interface to satisfy for writing is:
  * `Bool(x::MyType)`: define a conversion to `Bool` method
"""
struct BoolType <: JSONType end

"""
    JSON3.StructType(::Type{MyType}) = JSON3.NullType()

Declaring my type is `JSON3.NullType()` means it should map to the JSON value `null`.

Types already declared as `JSON3.NullType()` include:
  * `nothing`
  * `missing`

The interface to satisfy for reading is:
  * `MyType()`: an empty constructor for `MyType`
  * `JSON3.construct(::Type{MyType}, x::Nothing; kw...)`: alternatively, you may overload `JSON3.construct`

There is no interface for writing; if a custom type is declared as `JSON3.NullType()`, then the JSON value `null` will be written.
"""
struct NullType <: JSONType end

"""
    JSON3.StructType(::Type{MyType}) = JSON3.AbstractType()

When declaring my type as `JSON3.AbstractType()`, you must also define `JSON3.subtypes`, which should be a NamedTuple with subtype keys mapping to Julia subtype Type values. You may optionally define `JSON3.subtypekey` that indicates which JSON key should be used for identifying the appropriate concrete subtype. A quick example should help illustrate proper use of this `StructType`:
```julia
abstract type Vehicle end

struct Car <: Vehicle
    type::String
    make::String
    model::String
    seatingCapacity::Int
    topSpeed::Float64
end

struct Truck <: Vehicle
    type::String
    make::String
    model::String
    payloadCapacity::Float64
end

JSON3.StructType(::Type{Vehicle}) = JSON3.AbstractType()
JSON3.subtypekey(::Type{Vehicle}) = :type
JSON3.subtypes(::Type{Vehicle}) = (car=Car, truck=Truck)

car = JSON3.read(\"\"\"
{
    "type": "car",
    "make": "Mercedes-Benz",
    "model": "S500",
    "seatingCapacity": 5,
    "topSpeed": 250.1
}\"\"\", Vehicle)
```
Here we have a `Vehicle` type that is defined as a `JSON3.AbstractType()`. We also have two concrete subtypes, `Car` and `Truck`. In addition to the `StructType` definition, we also define `JSON3.subtypekey(::Type{Vehicle}) = :type`, which signals to JSON3 that, when parsing a JSON structure, when it encounters the `type` key, it should use the value, in our example it's `car`, to discover the appropriate concrete subtype to parse the structure as, in this case `Car`. The mapping of JSON subtype key value to Julia Type is defined in our example via `JSON3.subtypes(::Type{Vehicle}) = (car=Car, truck=Truck)`. Thus, `JSON3.AbstractType` is useful when the JSON structure to read includes a "subtype" key-value pair that can be used to parse a specific, concrete type; in our example, parsing the structure as a `Car` instead of a `Truck`.
"""
struct AbstractType <: StructType end

subtypekey(x::T) where {T} = subtypekey(T)
subtypekey(::Type{T}) where {T} = :type
subtypes(x::T) where {T} = subtypes(T)
subtypes(::Type{T}) where {T} = NamedTuple()

read(io::IO, ::Type{T}; kw...) where {T} = read(Base.read(io, String), T; kw...)
read(bytes::AbstractVector{UInt8}, ::Type{T}; kw...) where {T} = read(VectorString(bytes), T; kw...)

function read(str::AbstractString, ::Type{T}; kw...) where {T}
    buf = codeunits(str)
    len = length(buf)
    if len == 0
        error = UnexpectedEOF
        pos = 0
        @goto invalid
    end
    pos = 1
    b = getbyte(buf, pos)
    @wh
    pos, x = read(StructType(T), buf, pos, len, b, T; kw...)
    return x
@label invalid
    invalid(error, buf, pos, T)
end

read(::NoStructType, buf, pos, len, b, ::Type{T}; kw...) where {T} = throw(ArgumentError("$T doesn't have a defined `JSON3.StructType`"))

function read(::Struct, buf, pos, len, b, U::Union; kw...)
    # Julia implementation detail: Unions are sorted :)
    # This lets us avoid the below try-catch when U <: Union{Missing,T}
    if U.a === Nothing || U.a === Missing
        if buf[pos] == UInt8('n')
            return read(StructType(U.a), buf, pos, len, b, U.a)
        else
            return read(StructType(U.b), buf, pos, len, b, U.b; kw...)
        end
    end
    try
        return read(StructType(U.a), buf, pos, len, b, U.a; kw...)
    catch e
        return read(StructType(U.b), buf, pos, len, b, U.b; kw...)
    end
end

@inline function read(::Struct, buf, pos, len, b, ::Type{Any}; kw...)
    if b == UInt8('{')
        return read(ObjectType(), buf, pos, len, b, Dict{String, Any})
    elseif b == UInt8('[')
        return read(ArrayType(), buf, pos, len, b, Base.Array{Any})
    elseif b == UInt8('"')
        return read(StringType(), buf, pos, len, b, String)
    elseif b == UInt8('n')
        return read(NullType(), buf, pos, len, b, Nothing)
    elseif b == UInt8('t')
        return read(BoolType(), buf, pos, len, b, Bool)
    elseif b == UInt8('f')
        return read(BoolType(), buf, pos, len, b, Bool)
    elseif (UInt8('0') <= b <= UInt8('9')) || b == UInt8('-') || b == UInt8('+')
        float, code, pos = Parsers.typeparser(Float64, buf, pos, len, b, Int16(0), Parsers.OPTIONS)
        if code > 0
            int = unsafe_trunc(Int64, float)
            if int == float
                return pos, int
            else
                return pos, float
            end
        end
    end
@label invalid
    invalid(InvalidChar, buf, pos, Any)
end

StructType(::Type{<:AbstractString}) = StringType()
StructType(::Type{Symbol}) = StringType()
StructType(::Type{<:Enum}) = StringType()
StructType(::Type{Char}) = StringType()
StructType(::Type{UUID}) = StringType()
StructType(::Type{T}) where {T <: Dates.TimeType} = StringType()

function construct(::Type{Char}, str::String; kw...)
    if length(str) == 1
        return Char(str[1])
    else
        throw(ArgumentError("invalid conversion from json string to Char: '$str'"))
    end
end

function construct(::Type{E}, ptr::Ptr{UInt8}, len::Int; kw...) where {E <: Enum}
    @static if VERSION < v"1.2.0-DEV.272"
        Core.eval(parentmodule(E), _symbol(ptr, len))
    else
        sym = _symbol(ptr, len)
        for (k, v) in Base.Enums.namemap(E)
            sym == v && return E(k)
        end
        throw(ArgumentError("invalid $E string value: \"$(unsafe_string(ptr, len))\""))
    end
end

construct(T, str::String; kw...) = T(str)
construct(T, ptr::Ptr{UInt8}, len::Int; kw...) = construct(T, unsafe_string(ptr, len); kw...)
construct(::Type{Symbol}, ptr::Ptr{UInt8}, len::Int; kw...) = _symbol(ptr, len)
construct(::Type{T}, str::String; dateformat::Dates.DateFormat=Dates.default_format(T), kw...) where {T <: Dates.TimeType} = T(str, dateformat)

@inline function read(::StringType, buf, pos, len, b, ::Type{T}; kw...) where {T}
    if b != UInt8('"')
        error = ExpectedOpeningQuoteChar
        @goto invalid
    end
    pos += 1
    @eof
    strpos = pos
    strlen = 0
    escaped = false
    b = getbyte(buf, pos)
    while b != UInt8('"')
        if b == UInt8('\\')
            escaped = true
            # skip next character
            pos += 2
            strlen += 2
        else
            pos += 1
            strlen += 1
        end
        @eof
        b = getbyte(buf, pos)
    end
    ptr = pointer(buf, strpos)
    return pos + 1, escaped ? construct(T, unescape(PointerString(ptr, strlen)); kw...) : construct(T, ptr, strlen; kw...)

@label invalid
    invalid(error, buf, pos, T)
end

StructType(::Type{Bool}) = BoolType()

construct(T, bool::Bool; kw...) = T(bool)

@inline function read(::BoolType, buf, pos, len, b, ::Type{T}; kw...) where {T}
    if pos + 3 <= len &&
        b            == UInt8('t') &&
        buf[pos + 1] == UInt8('r') &&
        buf[pos + 2] == UInt8('u') &&
        buf[pos + 3] == UInt8('e')
        return pos + 4, construct(T, true; kw...)
    elseif pos + 4 <= len &&
        b            == UInt8('f') &&
        buf[pos + 1] == UInt8('a') &&
        buf[pos + 2] == UInt8('l') &&
        buf[pos + 3] == UInt8('s') &&
        buf[pos + 4] == UInt8('e')
        return pos + 5, construct(T, false; kw...)
    else
        invalid(InvalidChar, buf, pos, Bool)
    end
end

StructType(::Type{Nothing}) = NullType()
StructType(::Type{Missing}) = NullType()

construct(T, ::Nothing; kw...) = T()

@inline function read(::NullType, buf, pos, len, b, ::Type{T}; kw...) where {T}
    if pos + 3 <= len &&
        b            == UInt8('n') &&
        buf[pos + 1] == UInt8('u') &&
        buf[pos + 2] == UInt8('l') &&
        buf[pos + 3] == UInt8('l')
        return pos + 4, construct(T, nothing; kw...)
    else
        invalid(InvalidChar, buf, pos, T)
    end
end

StructType(::Type{<:Unsigned}) = NumberType()
StructType(::Type{<:Signed}) = NumberType()
StructType(::Type{<:AbstractFloat}) = NumberType()
numbertype(::Type{T}) where {T <: Real} = T
numbertype(x) = Float64
construct(T, x::Real; kw...) = T(x)

@inline function read(::NumberType, buf, pos, len, b, ::Type{T}; kw...) where {T}
    x, code, pos = Parsers.typeparser(numbertype(T), buf, pos, len, b, Int16(0), Parsers.OPTIONS)
    if code > 0
        return pos, construct(T, x; kw...)
    end
    invalid(InvalidChar, buf, pos, T)
end

StructType(::Type{<:AbstractArray}) = ArrayType()
StructType(::Type{<:AbstractSet}) = ArrayType()
StructType(::Type{<:Tuple}) = ArrayType()

construct(T, x::Vector{S}; kw...) where {S} = T(x)

@inline read(::ArrayType, buf, pos, len, b, ::Type{T}; kw...) where {T} = read(ArrayType(), buf, pos, len, b, T, Base.IteratorEltype(T) == Base.HasEltype() ? eltype(T) : Any; kw...)
@inline read(::ArrayType, buf, pos, len, b, ::Type{T}, ::Type{eT}; kw...) where {T, eT} = readarray(buf, pos, len, b, T, eT; kw...)
read(::ArrayType, buf, pos, len, b, ::Type{Tuple}, ::Type{eT}; kw...) where {eT} = readarray(buf, pos, len, b, Tuple, eT; kw...)

@inline function readarray(buf, pos, len, b, ::Type{T}, ::Type{eT}; kw...) where {T, eT}
    if b != UInt8('[')
        error = ExpectedOpeningArrayChar
        @goto invalid
    end
    pos += 1
    @eof
    b = getbyte(buf, pos)
    @wh
    vals = Vector{eT}(undef, 0)
    if b == UInt8(']')
        return pos + 1, construct(T, vals; kw...)
    end
    while true
        # positioned at start of value
        pos, y = read(StructType(eT), buf, pos, len, b, eT; kw...)
        push!(vals, y)
        @eof
        b = getbyte(buf, pos)
        @wh
        if b == UInt8(']')
            return pos + 1, construct(T, vals; kw...)
        elseif b != UInt8(',')
            error = ExpectedComma
            @goto invalid
        end
        pos += 1
        @eof
        b = getbyte(buf, pos)
        @wh
    end

@label invalid
    invalid(error, buf, pos, T)
end

@inline function read(::ArrayType, buf, pos, len, b, ::Type{T}, ::Type{eT}; kw...) where {T <: Tuple, eT}
    if b != UInt8('[')
        error = ExpectedOpeningArrayChar
        @goto invalid
    end
    pos += 1
    @eof
    b = getbyte(buf, pos)
    @wh
    if b == UInt8(']')
        pos += 1
        return pos, T()
    end
    N = fieldcount(T)
    Base.@nexprs 32 i -> begin
        # positioned at start of value
        eT_i = fieldtype(T, i)
        pos, x_i = read(StructType(eT_i), buf, pos, len, b, eT_i; kw...)
        @eof
        b = getbyte(buf, pos)
        @wh
        if N == i
            if b == UInt8(']')
                return pos + 1, Base.@ncall i tuple x
            else
                error = ExpectedClosingArrayChar
                @goto invalid
            end
        elseif b != UInt8(',')
            error = ExpectedComma
            @goto invalid
        end
        pos += 1
        @eof
        b = getbyte(buf, pos)
        @wh
    end
    vals = []
    for i = 33:N
        eT_i = fieldtype(T, i)
        pos, y = read(StructType(eT_i), buf, pos, len, b, eT_i; kw...)
        push!(vals, y)
        @eof
        b = getbyte(buf, pos)
        @wh
        if b == UInt8(']')
            pos += 1
            break
        elseif b != UInt8(',')
            error = ExpectedComma
            @goto invalid
        end
        pos += 1
        @eof
        b = getbyte(buf, pos)
        @wh
    end
    return pos, (x_1, x_2, x_3, x_4, x_5, x_6, x_7, x_8, x_9, x_10, x_11, x_12, x_13, x_14, x_15, x_16,
                  x_17, x_18, x_19, x_20, x_21, x_22, x_23, x_24, x_25, x_26, x_27, x_28, x_29, x_30, x_31, x_32, vals...)

@label invalid
    invalid(error, buf, pos, T)
end

StructType(::Type{<:AbstractDict}) = ObjectType()
StructType(::Type{<:NamedTuple}) = ObjectType()
StructType(::Type{<:Pair}) = ObjectType()

keyvaluepairs(x) = pairs(x)
keyvaluepairs(x::Pair) = (x,)

construct(::Type{Dict{K, V}}, x::Dict{K, V}; kw...) where {K, V} = x
construct(T, x::Dict{K, V}; kw...) where {K, V} = T(x)

construct(::Type{NamedTuple}, x::Dict; kw...) = NamedTuple{Tuple(keys(x))}(values(x))
construct(::Type{NamedTuple{names}}, x::Dict; kw...) where {names} = NamedTuple{names}(Tuple(x[nm] for nm in names))
construct(::Type{NamedTuple{names, types}}, x::Dict; kw...) where {names, types} = NamedTuple{names, types}(Tuple(x[nm] for nm in names))

keyvalue(::Type{Symbol}, escaped, ptr, len) = escaped ? Symbol(unescape(PointerString(ptr, len))) : _symbol(ptr, len)
keyvalue(::Type{T}, escaped, ptr, len) where {T} = escaped ? construct(T, unescape(PointerString(ptr, len))) : construct(T, unsafe_string(ptr, len))

@inline read(::ObjectType, buf, pos, len, b, ::Type{T}; kw...) where {T} = read(ObjectType(), buf, pos, len, b, T, Symbol, Any; kw...)
@inline read(::ObjectType, buf, pos, len, b, ::Type{T}; kw...) where {T <: NamedTuple} = read(ObjectType(), buf, pos, len, b, T, Symbol, Any; kw...)
@inline read(::ObjectType, buf, pos, len, b, ::Type{Dict}; kw...) = read(ObjectType(), buf, pos, len, b, Dict, String, Any; kw...)
@inline read(::ObjectType, buf, pos, len, b, ::Type{T}; kw...) where {T <: AbstractDict} = read(ObjectType(), buf, pos, len, b, T, keytype(T), valtype(T); kw...)

@inline function read(::ObjectType, buf, pos, len, b, ::Type{T}, ::Type{K}, ::Type{V}; kw...) where {T, K, V}
    if b != UInt8('{')
        error = ExpectedOpeningObjectChar
        @goto invalid
    end
    pos += 1
    @eof
    b = getbyte(buf, pos)
    @wh
    x = Dict{K, V}()
    if b == UInt8('}')
        return pos + 1, construct(T, x; kw...)
    elseif b != UInt8('"')
        error = ExpectedOpeningQuoteChar
        @goto invalid
    end
    pos += 1
    @eof
    while true
        keypos = pos
        keylen = 0
        escaped = false
        # read first key character
        b = getbyte(buf, pos)
        # positioned at first character of object key
        while b != UInt8('"')
            if b == UInt8('\\')
                escaped = true
                # skip next character
                pos += 2
                keylen += 2
            else
                pos += 1
                keylen += 1
            end
            @eof
            b = getbyte(buf, pos)
        end
        key = keyvalue(K, escaped, pointer(buf, keypos), keylen)
        pos += 1
        @eof
        b = getbyte(buf, pos)
        @wh
        if b != UInt8(':')
            error = ExpectedSemiColon
            @goto invalid
        end
        pos += 1
        @eof
        b = getbyte(buf, pos)
        @wh
        # now positioned at start of value
        pos, y = read(StructType(V), buf, pos, len, b, V; kw...)
        x[key] = y
        @eof
        b = getbyte(buf, pos)
        @wh
        if b == UInt8('}')
            return pos + 1, construct(T, x; kw...)
        elseif b != UInt8(',')
            error = ExpectedComma
            @goto invalid
        end
        pos += 1
        @eof
        b = getbyte(buf, pos)
        @wh
        if b != UInt8('"')
            error = ExpectedOpeningQuoteChar
            @goto invalid
        end
        pos += 1
        @eof
    end

@label invalid
    invalid(error, buf, pos, Object)
end

@inline function read(::Mutable, buf, pos, len, b, ::Type{T}; kw...) where {T}
    if b != UInt8('{')
        error = ExpectedOpeningObjectChar
        @goto invalid
    end
    pos += 1
    @eof
    b = getbyte(buf, pos)
    @wh
    x = T()
    if b == UInt8('}')
        pos += 1
        return pos, x
    elseif b != UInt8('"')
        error = ExpectedOpeningQuoteChar
        @goto invalid
    end
    N = fieldcount(T)
    nms = names(T)
    excl = excludes(T)
    kwargs = keywordargs(T)
    pos += 1
    @eof
    while true
        keypos = pos
        keylen = 0
        escaped = false
        b = getbyte(buf, pos)
        while b != UInt8('"')
            if b == UInt8('\\')
                escaped = true
                # skip next character
                pos += 2
                keylen += 2
            else
                pos += 1
                keylen += 1
            end
            @eof
            b = getbyte(buf, pos)
        end
        key = keyvalue(Symbol, escaped, pointer(buf, keypos), keylen)
        key = julianame(nms, key)
        pos += 1
        @eof
        b = getbyte(buf, pos)
        @wh
        if b != UInt8(':')
            error = ExpectedSemiColon
            @goto invalid
        end
        pos += 1
        @eof
        b = getbyte(buf, pos)
        @wh
        is_included = !symbolin(excl, key)
        # unroll the first 32 field checks to avoid dynamic dispatch if possible
        Base.@nif(
            32,
            i -> (i <= N && fieldname(T, i) === key),
            i -> begin
                FT_i = fieldtype(T, i)
                if isempty(kwargs)
                    pos, y_i = read(StructType(FT_i), buf, pos, len, b, FT_i; kw...)
                else
                    pos, y_i = read(StructType(FT_i), buf, pos, len, b, FT_i; kwargs[fieldname(T, i)]...)
                end
                is_included && setfield!(x, i, y_i)
            end,
            i -> begin
                is_field_still_unread = true
                for j in 33:N
                    fieldname(T, j) === key || continue
                    FT_j = fieldtype(T, j)
                    if isempty(kwargs)
                        pos, y_j = read(StructType(FT_j), buf, pos, len, b, FT_j; kw...)
                    else
                        pos, y_j = read(StructType(FT_j), buf, pos, len, b, FT_j; kwargs[fieldname(T, j)]...)
                    end
                    is_included && setfield!(x, j, y_j)
                    is_field_still_unread = false
                    break
                end
                if is_field_still_unread
                    pos, _ = read(Struct(), buf, pos, len, b, Any)
                end
            end
        )
        @eof
        b = getbyte(buf, pos)
        @wh
        if b == UInt8('}')
            pos += 1
            return pos, x
        elseif b != UInt8(',')
            error = ExpectedComma
            @goto invalid
        end
        pos += 1
        @eof
        b = getbyte(buf, pos)
        @wh
        if b != UInt8('"')
            error = ExpectedOpeningQuoteChar
            @goto invalid
        end
        pos += 1
        @eof
    end

@label invalid
    invalid(error, buf, pos, T)
end

@inline function read(::Struct, buf, pos, len, b, ::Type{T}; kw...) where {T}
    if b != UInt8('{')
        error = ExpectedOpeningObjectChar
        @goto invalid
    end
    pos += 1
    @eof
    b = getbyte(buf, pos)
    @wh
    if b == UInt8('}')
        pos += 1
        return pos, T()
    elseif b != UInt8('"')
        error = ExpectedOpeningQuoteChar
        @goto invalid
    end
    pos += 1
    @eof
    N = fieldcount(T)
    Base.@nexprs 32 i -> begin
        pos, x_i = readvalue(buf, pos, len, fieldtype(T, i); kw...)
        if N == i
            return pos, Base.@ncall i T x
        end
    end
    vals = []
    for i = 33:N
        pos, y = readvalue(buf, pos, len, fieldtype(T, i); kw...)
        push!(vals, y)
    end
    return pos, T(x_1, x_2, x_3, x_4, x_5, x_6, x_7, x_8, x_9, x_10, x_11, x_12, x_13, x_14, x_15, x_16,
                  x_17, x_18, x_19, x_20, x_21, x_22, x_23, x_24, x_25, x_26, x_27, x_28, x_29, x_30, x_31, x_32, vals...)

@label invalid
    invalid(error, buf, pos, T)
end

@inline function readvalue(buf, pos, len, ::Type{T}; kw...) where {T}
    b = getbyte(buf, pos)
    while b != UInt8('"')
        pos += ifelse(b == UInt8('\\'), 2, 1)
        @eof
        b = getbyte(buf, pos)
    end
    pos += 1
    @eof
    b = getbyte(buf, pos)
    @wh
    if b != UInt8(':')
        error = ExpectedSemiColon
        @goto invalid
    end
    pos += 1
    @eof
    b = getbyte(buf, pos)
    @wh
    # read value
    pos, y = read(StructType(T), buf, pos, len, b, T; kw...)
    @eof
    b = getbyte(buf, pos)
    @wh
    if b == UInt8('}')
        pos += 1
        return pos, y
    elseif b != UInt8(',')
        error = ExpectedComma
        @goto invalid
    end
    pos += 1
    @eof
    b = getbyte(buf, pos)
    @wh
    if b != UInt8('"')
        error = ExpectedOpeningQuoteChar
        @goto invalid
    end
    pos += 1
    @eof
    return pos, y
@label invalid
    invalid(error, buf, pos, T)
end

@inline function read(::AbstractType, buf, pos, len, b, ::Type{T}; kw...) where {T}
    startpos = pos
    startb = b
    if b != UInt8('{')
        error = ExpectedOpeningObjectChar
        @goto invalid
    end
    pos += 1
    @eof
    b = getbyte(buf, pos)
    @wh
    if b == UInt8('}')
        throw(ArgumentError("invalid json abstract type"))
    elseif b != UInt8('"')
        error = ExpectedOpeningQuoteChar
        @goto invalid
    end
    pos += 1
    @eof
    types = subtypes(T)
    skey = subtypekey(T)
    while true
        keypos = pos
        keylen = 0
        escaped = false
        b = getbyte(buf, pos)
        while b != UInt8('"')
            if b == UInt8('\\')
                escaped = true
                # skip next character
                pos += 2
                keylen += 2
            else
                pos += 1
                keylen += 1
            end
            @eof
            b = getbyte(buf, pos)
        end
        key = keyvalue(Symbol, escaped, pointer(buf, keypos), keylen)
        pos += 1
        @eof
        b = getbyte(buf, pos)
        @wh
        if b != UInt8(':')
            error = ExpectedSemiColon
            @goto invalid
        end
        pos += 1
        @eof
        b = getbyte(buf, pos)
        @wh
        # read value
        pos, val = read(Struct(), buf, pos, len, b, Any)
        if key == skey
            TT = types[Symbol(val)]
            return read(StructType(TT), buf, startpos, len, startb, TT; kw...)
        end
        @eof
        b = getbyte(buf, pos)
        @wh
        if b == UInt8('}')
            pos += 1
            throw(ArgumentError("invalid json abstract type: didn't find subtypekey"))
        elseif b != UInt8(',')
            error = ExpectedComma
            @goto invalid
        end
        pos += 1
        @eof
        b = getbyte(buf, pos)
        @wh
        if b != UInt8('"')
            error = ExpectedOpeningQuoteChar
            @goto invalid
        end
        pos += 1
        @eof
    end

@label invalid
    invalid(error, buf, pos, T)
end
