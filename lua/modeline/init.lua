local co, api, iter = coroutine, vim.api, vim.iter
local p, hl = require('modeline.provider'), api.nvim_set_hl

local function stl_format(name, val)
  return ('%%#ModeLine%s#%s%%*'):format(name, val)
end

local function default()
  local comps = {
    p.gitinfo(),
    p.fileinfo(),
    ' %=',
    [[%{(bufname() !=# '' && &bt != 'terminal' ? '(' : '')}]],
    p.filetype(),
    p.diagnostic(),
    [[%{(bufname() !=# '' && &bt != 'terminal' ? ')' : '')}]],
    p.progress(),
    p.lsp(),
    '   ',
    p.encoding(),
    p.eol(),
    '   ',
    p.position_info(),
  }
  local e, pieces = {}, {}
  iter(ipairs(comps))
    :map(function(key, item)
      if type(item) == 'string' then
        pieces[#pieces + 1] = item
      elseif type(item.stl) == 'string' then
        pieces[#pieces + 1] = stl_format(item.name, item.stl)
      else
        pieces[#pieces + 1] = item.default and stl_format(item.name, item.default) or ''
        for _, event in ipairs(item.event or {}) do
          local ev, pattern = unpack(vim.split(event, ' '))
          e[ev] = e[ev] or {}
          e[ev][#e[ev] + 1] = { idx = key, pattern = pattern }
        end
      end
      if item.attr and item.name then
        hl(0, ('ModeLine%s'):format(item.name), item.attr)
      end
    end)
    :totable()
  return comps, e, pieces
end

local function render(comps, events, pieces)
  return co.create(function(args)
    while true do
      local to_update = {}
      if args == "ModeLineInit" then
        for i, comp in ipairs(comps) do
          if type(comp) == 'table' and type(comp.stl) == 'function' then
            to_update[i] = true
          end
        end
      else
        local entries = events[args.event]
        if entries then
          for _, entry in ipairs(entries) do
            if not entry.pattern or (args.event == 'User' and args.match == entry.pattern) then
              to_update[entry.idx] = true
            end
          end
        end
      end

      for idx, _ in pairs(to_update) do
        local comp = comps[idx]
        if comp.async then
          local child = comp.stl()
          coroutine.resume(child, pieces, idx)
        else
          pieces[idx] = stl_format(comp.name, comp.stl(args))
        end
      end
      vim.opt.stl = table.concat(pieces)
      args = co.yield()
    end
  end)
end

local colors = {
  bg = vim.api.nvim_get_hl(0, { name = 'StatusLine' }).bg or 'back',
  fg = '#d8dee9',
  yellow = '#ebcb8b',
  cyan = '#88c0d0',
  green = '#a3be8c',
  orange = '#d08770',
  magenta = '#b48ead',
  blue = '#5e81ac',
  red = '#bf616a'
}

local function set_highlights()
  vim.api.nvim_set_hl(0, 'ModeLineFile', { bg = colors.bg, fg = colors.cyan, bold = false, })
  vim.api.nvim_set_hl(0, 'ModeLineGitHead', { bg = colors.bg, fg = colors.green })
  vim.api.nvim_set_hl(0, 'ModeLineLsp', { bg = colors.bg, fg = colors.blue, italic = true, })
  vim.api.nvim_set_hl(0, 'ModeLineEOL', { bg = colors.bg, fg = colors.blue })
  -- vim.api.nvim_set_hl(0, 'ModeLinePosition', { bg = colors.bg, fg = colors.magenta })
  vim.api.nvim_set_hl(0, 'ModeLineDocumentSymbol', { bg = colors.bg, fg = colors.magenta })
end

return {
  setup = function()
    set_highlights()

    local comps, events, pieces = default()
    local stl_render = render(comps, events, pieces)

    local function update(args)
      local ok, res = co.resume(stl_render, args)
      if not ok then
        vim.notify('[ModeLine] render failed: ' .. tostring(res), vim.log.levels.ERROR)
      end
    end

    for e, entries in pairs(events) do
      local patterns = {}
      if e == 'User' then
        for _, entry in ipairs(entries) do
          if entry.pattern then
            table.insert(patterns, entry.pattern)
          end
        end
      end

      api.nvim_create_autocmd(e, {
        pattern = #patterns > 0 and patterns or nil,
        callback = function(args)
          update(args)
        end,
        desc = '[ModeLine] update',
      })
    end

    vim.schedule(function()
      update("ModeLineInit")
    end)
  end,
}
