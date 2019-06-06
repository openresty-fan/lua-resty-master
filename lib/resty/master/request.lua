-- Copyright (C) Jingli Chen (Wine93)
-- Copyright (C) Jinzheng Zhang (tianchaijz)


local core = require "resty.master.core"


local type = type
local setmetatable = setmetatable


local _M = {}
local _mt = { __index = _M }
local _handlers = {}


_M.REWRITE_PHASE       = core.REWRITE_PHASE
_M.ACCESS_PHASE        = core.ACCESS_PHASE
_M.CONTENT_PHASE       = core.CONTENT_PHASE
_M.HEADER_FILTER_PHASE = core.HEADER_FILTER_PHASE
_M.BODY_FILTER_PHASE   = core.BODY_FILTER_PHASE
_M.LOG_PHASE           = core.LOG_PHASE


local function is_tbl(obj) return type(obj) == "table" end


local function load_module_phase(module, phase)
    if is_tbl(module) then
        local export = module[2]
        if is_tbl(export) and export[phase] == true then
            module = module[1]
        else
            return
        end
    end
    return module, require(module)[phase]
end


local function phase_handler(modules, phase)
    local chain
    local index = {}
    for idx = #modules, 1, -1 do
        local module, ph = load_module_phase(modules[idx], phase)
        if ph then
            chain = { next = chain, handler = ph.handler }
            index[module] = chain
        end
    end
    return { chain = chain, index = index }
end


local function next_handler(self, phase, module)
    local ph = _handlers[self._type][phase]
    if not ph then
        return
    end

    local chain = ph.index[module].next
    if chain then
        return chain.handler(self)
    end
end


local function run_phase(self)
    local ph = _handlers[self._type][self._phase]
    local chain = ph.chain
    if chain then
        chain.handler(self)
    end
end


function _M.new(typ)
    local r = { _ctx = {}, _type = typ, _phase = -1 }
    return setmetatable(r, _mt)
end


function _M.register(typ, modules)
    local handler = {}
    for phase = _M.REWRITE_PHASE, _M.LOG_PHASE, 1 do
        handler[phase] = phase_handler(modules, phase)
    end
    _handlers[typ] = handler
end


function _M.get_type(self)
    return self._type
end


local function set_type(self, typ)
    self._type = typ
end
_M.set_type = set_type


local function set_phase(self, phase)
    self._phase = phase
end
_M.set_phase = set_phase


function _M.get_phase(self)
    return self._phase
end


function _M.get_module_ctx(self, module)
    return self._ctx[module]
end


function _M.set_module_ctx(self, module, ctx)
    self._ctx[module] = ctx
end


function _M.next_handler(self, module)
    return next_handler(self, self._phase, module)
end


-- content -> header filter -> content
function _M.run(self, phase)
    local old_phase = self._phase
    set_phase(self, phase)
    run_phase(self)
    set_phase(self, old_phase)
end


function _M.exec(self, typ)
    local old_phase = self._phase
    set_type(self, typ)
    run_phase(self)
    set_phase(self, old_phase)
end


return _M
