local ffi = require('ffi')
local C = ffi.C
require('pllj.pg.init_c')
local NULL = require('pllj.pg.c').NULL

local syscache = require('pllj.pg.syscache')
local macro = require('pllj.pg.macro')

local function get_oid_from_name(sptr)
    local typeId = ffi.new("Oid[?]", 1)
    local typmod = ffi.new("int32[?]", 1)
    C.parseTypeString(sptr, typeId, typmod, true)
    return tonumber(typeId[0])
end

local composite_tuple_descriptions = {}
local function get_pg_typeinfo(oid)
    local t = C.SearchSysCache(syscache.enum.TYPEOID, --[[ObjectIdGetDatum]] oid, 0, 0, 0);
    local tstruct = ffi.cast('Form_pg_type', macro.GETSTRUCT(t));
    --    local result = {
    --        typlen = tstruct.typlen,
    --        typtype = tstruct.typtype,
    --        typalign = tstruct.typalign,
    --        typbyval = tstruct.typbyval,
    --        typelem = tstruct.typelem,
    --        typinput = tstruct.typinput,
    --        typoutput = tstruct.typoutput
    --    }
    local tuple_desc = composite_tuple_descriptions[oid]
    if not tuple_desc and (tstruct.typtype == C.TYPTYPE_COMPOSITE) then

        local tdesc = C.lookup_rowtype_tupdesc_noerror(oid, tstruct.typtypmod, true)
        if tdesc ~= NULL then

            local prev = C.CurrentMemoryContext
            C.CurrentMemoryContext = C.TopMemoryContext

            tuple_desc = C.CreateTupleDescCopyConstr(tdesc);
            C.CurrentMemoryContext = prev
            C.BlessTupleDesc(tuple_desc);
            macro.ReleaseTupleDesc(tdesc);


            composite_tuple_descriptions[oid] = tuple_desc
        end

    end
    local result = {
        data = tstruct,
        tuple_desc = tuple_desc,
        _free = function() C.ReleaseSysCache(t) end
    }

    return result;
end

return {
    get_oid_from_name = get_oid_from_name,
    get_pg_typeinfo = get_pg_typeinfo
}

