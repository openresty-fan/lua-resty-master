-- Copyright (C) Jingli Chen (Wine93)
-- Copyright (C) Jinzheng Zhang (tianchaijz)


local core = require "resty.master.http.core"


local type = type
local ipairs = ipairs
local assert = assert
local setmetatable = setmetatable


local _M = {}
local _mt = { __index = _M }
local _handlers = {}
local _inits = {}  -- init worker hooks
local _inits_loaded = {}


_M.REWRITE_PHASE       = core.REWRITE_PHASE
_M.ACCESS_PHASE        = core.ACCESS_PHASE
_M.CONTENT_PHASE       = core.CONTENT_PHASE
_M.HEADER_FILTER_PHASE = core.HEADER_FILTER_PHASE
_M.BODY_FILTER_PHASE   = core.BODY_FILTER_PHASE
_M.LOG_PHASE           = core.LOG_PHASE


local function is_tbl(obj) return type(obj) == "table" end


local function load_module_phase(module, phase)
    local phase_ctx
    if is_tbl(module) then
        local export = module.export
        if is_tbl(export) and not export[phase] then
            return
        end

        local ctx = module.ctx
        if is_tbl(ctx) then
            phase_ctx = ctx[phase]
        end

        module = module[1]
    end
    local mod = assert(require(module), module)
    return module, mod[phase], phase_ctx or {}
end


local function phase_handler(modules, phase)
    local chain
    local index = {}
    for idx = #modules, 1, -1 do
        local module, ph, ctx = load_module_phase(modules[idx], phase)
        if ph then
            chain = { next = chain, handler = ph.handler, ctx = ctx }
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
        return chain.handler(self, chain.ctx)
    end
end


local function run_phase(self)
    local ph = _handlers[self._type][self._phase]
    local chain = ph.chain
    if chain then
        chain.handler(self, chain.ctx)
    end
end


function _M.new(typ)
    local r = { _ctx = {}, _type = typ, _phase = 0 }
    return setmetatable(r, _mt)
end


function _M.register(typ, modules)
    local handler = {}
    for phase = _M.REWRITE_PHASE, _M.LOG_PHASE, 1 do
        handler[phase] = phase_handler(modules, phase)
    end
    _handlers[typ] = handler

    for _, mod in ipairs(modules) do
        local module, init, ctx = load_module_phase(mod, core.INIT_WORKER)
        if init and init.handler then
            if not ctx then
                if _inits_loaded[module] then
                    ngx.log(ngx.ERR, module,
                            " init multiple times without context")
                else
                    _inits_loaded[module] = true
                end
            end

            _inits[#_inits + 1] = { init.handler, ctx }
        end
    end
end


function _M.init()
    local handler, ctx
    for _, init in ipairs(_inits) do
        handler, ctx = init[1], init[2]
        handler(ctx)
    end

    _inits = {}
    _inits_loaded = {}
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
