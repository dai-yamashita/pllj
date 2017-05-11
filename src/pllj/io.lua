local typeto = require('pllj.pg.to_lua').typeto

local datumfor = require('pllj.pg.to_pg').datumfor
local macro = require('pllj.pg.macro')

local ffi = require('ffi')
local C = ffi.C
local get_pg_typeinfo = require('pllj.pg.type_info').get_pg_typeinfo

local field  = {
    DATUM = 1,
    OID = 2,
    TYPEINFO = 3,
    INPUT = 4,
    OUTPUT = 5,
    LUAVAL = 6,
}

local raw_datum = {
    __tostring = function(self)
        local charPtr = C.OutputFunctionCall(self[field.OUTPUT], self[field.DATUM])
        return ffi.string(charPtr)
    end
}

local io = {}

local isNull = ffi.new("bool[?]", 1)



local function create_converter_tolua(oid)
    local typeinfo = get_pg_typeinfo(oid)
    local free = typeinfo._free
    local tuple_desc = typeinfo.tuple_desc
    typeinfo = typeinfo.data
    local result
    if typeinfo.typtype == C.TYPTYPE_BASE then

        local input = ffi.new("FmgrInfo[?]", 1)
        local output = ffi.new("FmgrInfo[?]", 1)
        C.fmgr_info_cxt(typeinfo.typinput, input, C.TopMemoryContext);
        C.fmgr_info_cxt(typeinfo.typoutput, output, C.TopMemoryContext);

        result = function (datum)
            local value = {
                [field.DATUM] = datum,
                [field.OID] = oid,
                [field.TYPEINFO] = typeinfo,
                [field.INPUT] = input,
                [field.OUTPUT] = output
            }
            setmetatable(value, raw_datum)

            return value
        end
    elseif typeinfo.typtype == C.TYPTYPE_COMPOSITE then

        local input = ffi.new("FmgrInfo[?]", 1)
        local output = ffi.new("FmgrInfo[?]", 1)
        C.fmgr_info_cxt(typeinfo.typinput, input, C.TopMemoryContext);
        C.fmgr_info_cxt(typeinfo.typoutput, output, C.TopMemoryContext);

        result = function (datum)
            local out = {}
            local tup = ffi.cast('HeapTupleHeader', macro.PG_DETOAST_DATUM(datum))
            for k = 0, tuple_desc.natts-1 do
                local attr = tuple_desc.attrs[k]
                local key =  (ffi.string(ffi.cast('const char *', attr.attname)))
                local value = C.GetAttributeByNum(tup, attr.attnum, isNull)
                if isNull[0] == false then
                    out[key] = value
                end

            end
            local value = {
                [field.DATUM] = datum,
                [field.OID] = oid,
                [field.TYPEINFO] = typeinfo,
                [field.INPUT] = input,
                [field.OUTPUT] = output,
                [field.LUAVAL] = out
            }
            setmetatable(value, raw_datum)

            return value

        end

    end

    free()
    return result

end

local function create_converter_topg(oid)
    local typeinfo = get_pg_typeinfo(oid)
    local free = typeinfo._free;
    typeinfo = typeinfo.data
    local result
    --if typeinfo.typtype == C.TYPTYPE_BASE then

        local input = ffi.new("FmgrInfo[?]", 1)
        C.fmgr_info_cxt(typeinfo.typinput, input, C.TopMemoryContext);

        result = function (value)
            if (type(value) == "string") then
                local inoid = oid
                if typeinfo.typelem ~=0 then
                    inoid = typeinfo.typelem
                end
                local text = tostring(value)
                local prev = C.CurrentMemoryContext
                C.CurrentMemoryContext = C.CurTransactionContext
                local datum = C.InputFunctionCall(input, ffi.cast('char*', text), inoid, -1)
                C.CurrentMemoryContext = prev

                return datum
            elseif (type(value) == "table" and getmetatable(value) == raw_datum) then
                return value[field.DATUM]
            end
        end
    --end
    free()
    return result

end

function io.to_lua(typeoid)
    local to_lua = typeto[typeoid]
    if not to_lua then
        to_lua = create_converter_tolua(typeoid) or function(datum) return datum end
        typeto[typeoid] = to_lua
    end
    return to_lua
end

function io.to_pg(typeoid)
    local to_pg = datumfor[typeoid]
    if not to_pg then
        to_pg = create_converter_topg(typeoid) or function(datum) return datum end
        datumfor[typeoid] = to_pg
    end
    return to_pg
end

io.datumfor = datumfor

--local function datum_to_value(datum, atttypid)
--
--    local func = typeto[atttypid]
--    if (func) then
--        return func(datum)
--    end
--    return datum --TODO other types
--    --print("SC = "..tonumber(syscache.enum.TYPEOID))
--    --type = C.SearchSysCache(syscache.enum.TYPEOID, ObjectIdGetDatum(oid), 0, 0, 0);
--end

return io