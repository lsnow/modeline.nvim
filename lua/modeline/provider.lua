local api, lsp, diagnostic, M = vim.api, vim.lsp, vim.diagnostic, {}
local fnamemodify = vim.fn.fnamemodify

local function get_stl_bg()
  return api.nvim_get_hl(0, { name = 'StatusLine' }).bg or 'back'
end

local function group_name(group)
  return 'ModeLine' .. group
end

local stl_bg = get_stl_bg()
local function stl_attr(group)
  local color = api.nvim_get_hl(0, { name = group_name(group), link = false })
  return {
    bg = get_stl_bg(),
    fg = color.fg,
  }
end

local function int_to_rgb(color)
  return {
    r = bit.band(bit.rshift(color, 16), 0xFF),
    g = bit.band(bit.rshift(color, 8), 0xFF),
    b = bit.band(color, 0xFF)
  }
end

-- W3C: 0.2126 * R + 0.7152 * G + 0.0722 * B
local function get_luminance(rgb)
  local rs = rgb.r / 255
  local gs = rgb.g / 255
  local bs = rgb.b / 255

  -- Gamma
  local function correct(c)
    return c <= 0.03928 and c / 12.92 or math.pow((c + 0.055) / 1.055, 2.4)
  end

  local r = correct(rs)
  local g = correct(gs)
  local b = correct(bs)

  return 0.2126 * r + 0.7152 * g + 0.0722 * b
end

local function scale_color(color, target_max_val)
  local rgb = int_to_rgb(color)

  local max_val = math.max(rgb.r, rgb.g, rgb.b)
  if max_val == 0 then
    return bit.lshift(target_max_val, 16) + bit.lshift(target_max_val, 8) + target_max_val
  end

  local scale = target_max_val / max_val

  local r = math.min(255, math.floor(rgb.r * scale))
  local g = math.min(255, math.floor(rgb.g * scale))
  local b = math.min(255, math.floor(rgb.b * scale))

  return bit.lshift(r, 16) + bit.lshift(g, 8) + b
end

local function enhance_contrast(orig)
  local bg_int = stl_bg
  local fg_int = orig

  local bg_rgb = int_to_rgb(bg_int)
  local fg_rgb = int_to_rgb(fg_int)

  local bg_lum = get_luminance(bg_rgb)
  local fg_lum = get_luminance(fg_rgb)

  local new_color = fg_int

  if bg_lum < 0.5 then
    if fg_lum < 0.6 then
      new_color = scale_color(fg_int, 255)
    end
  else
    if fg_lum > 0.4 then
      new_color = scale_color(fg_int, 100)
    end
  end

  return new_color
end

local function group_fmt(prefix, name, val)
  return ('%%#ModeLine%s%s#%s%%*'):format(prefix, name, val)
end

local mode_alias = {
  --Normal
  ['n'] = 'Normal',
  ['no'] = 'O-Pending',
  ['nov'] = 'O-Pending',
  ['noV'] = 'O-Pending',
  ['no\x16'] = 'O-Pending',
  ['niI'] = 'Normal',
  ['niR'] = 'Normal',
  ['niV'] = 'Normal',
  ['nt'] = 'Normal',
  ['ntT'] = 'Normal',
  ['v'] = 'Visual',
  ['vs'] = 'Visual',
  ['V'] = 'V-Line',
  ['Vs'] = 'V-Line',
  ['\x16'] = 'V-Block',
  ['\x16s'] = 'V-Block',
  ['s'] = 'Select',
  ['S'] = 'S-Line',
  ['\x13'] = 'S-Block',
  ['i'] = 'Insert',
  ['ic'] = 'Insert',
  ['ix'] = 'Insert',
  ['R'] = 'Replace',
  ['Rc'] = 'Replace',
  ['Rx'] = 'Replace',
  ['Rv'] = 'V-Replace',
  ['Rvc'] = 'V-Replace',
  ['Rvx'] = 'V-Replace',
  ['c'] = 'Command',
  ['cv'] = 'Ex',
  ['ce'] = 'Ex',
  ['r'] = 'Replace',
  ['rm'] = 'More',
  ['r?'] = 'Confirm',
  ['!'] = 'Shell',
  ['t'] = 'Terminal',
}

function _G.ml_mode()
  local mode = api.nvim_get_mode().mode
  local m = mode_alias[mode] or mode_alias[string.sub(mode, 1, 1)] or 'UNK'
  return m:sub(1, 3):upper()
end

function M.fileinfo()
  local name = vim.fn.expand('%:~')

  if name == '' then
    name = '[No Name]'
  else
    local relative_to_home = name --vim.fn.fnamemodify(name, ':~')
    local relative_to_cwd = vim.fn.fnamemodify(name, ':.')

    if #relative_to_cwd < #relative_to_home then
      name = relative_to_cwd
    else
      name = relative_to_home
    end

    local max_length = 50
    if #name > max_length then
      local parts = vim.split(name, '/')
      if #parts > 3 then
        name = table.concat(vim.list_slice(parts, 1, 2), '/') .. '/.../' .. parts[#parts]
      else
        name = '...' .. name:sub(-(max_length - 3))
      end
    end
  end
  return {
    stl = ' ' .. name .. [[%{(&modified&&&readonly?' RO*':(&modified?' **':(&readonly?' RO':'')))}  ]],
    name = 'fileinfo',
    event = { 'BufEnter' },
    attr = stl_attr('File'),
  }
end

function M.position_info()
  return {
    stl = '%b(0x%B) %l,%c%V %P',
    name = 'position',
    event = { 'BufEnter' },
    attr = stl_attr('Position'),
  }
end

function M.filetype()
  local ft = api.nvim_get_option_value('filetype', { buf = 0 })
  -- local up = ft:sub(1, 1):upper()
  -- if #ft == 1 then
  --   return up
  -- end
  -- local alias = { cpp = 'C++' }
  -- return alias[ft] or up .. ft:sub(2, #ft)
  return {
    name = 'filetype',
    stl = ft,
    event = { 'BufEnter' },
  }
end

function M.progress()
  local spinner = { '⣶', '⣧', '⣏', '⡟', '⠿', '⢻', '⣹', '⣼' }
  local idx = 1
  return {
    stl = function(args)
      if args.data and args.data.params then
        local val = args.data.params.value
        if val.message and val.kind ~= 'end' then
          idx = idx + 1 > #spinner and 1 or idx + 1
          return ('%s'):format(spinner[idx - 1 > 0 and idx - 1 or 1])
        end
      end
      return ''
    end,
    name = 'LspProgress',
    event = { 'LspProgress' },
    attr = stl_attr('Type'),
  }
end

function M.lsp()
  return {
    stl = function(args)
      local clients = lsp.get_clients({ bufnr = 0 })
      if #clients == 0 then
        return ''
      end
      local root_dir = 'single'
      local client_names = vim
        .iter(clients)
        :map(function(client)
          if client.root_dir then
            root_dir = client.root_dir
          end
          return client.name
        end)
        :totable()

      local msg = ('[%s:%s]'):format(
        table.concat(client_names, ','),
        root_dir ~= 'single' and fnamemodify(root_dir, ':t') or 'single'
      )
      if args.data and args.data.params then
        local val = args.data.params.value
        if val.message and val.kind ~= 'end' then
          msg = ('%s %s%s'):format(
            val.title,
            (val.message and val.message .. ' ' or ''),
            (val.percentage and val.percentage .. '%' or '')
          )
        end
      elseif args.event == 'LspDetach' then
        msg = ''
      end
      return '   %-20s' .. msg
    end,
    name = 'Lsp',
    event = { 'LspProgress', 'LspAttach', 'LspDetach', 'BufEnter' },
    attr = stl_attr('LSP'),
  }
end

function M.gitinfo()
  local alias = { 'Head', 'Add', 'Change', 'Delete' }
  for i = 2, 4 do
    local color = api.nvim_get_hl(0, { name = 'Diff' .. alias[i] })
    api.nvim_set_hl(0, 'ModeLineGit' .. alias[i], { fg = enhance_contrast(color.bg), bg = stl_bg })
  end
  return {
    stl = function()
      return coroutine.create(function(pieces, idx)
        local signs = { 'Git:', '+', '~', '-' }
        local order = { 'head', 'added', 'changed', 'removed' }

        local ok, dict = pcall(api.nvim_buf_get_var, 0, 'gitsigns_status_dict')
        if not ok or vim.tbl_isempty(dict) then
          return ''
        end
        if dict['head'] == '' then
          local co = coroutine.running()
          vim.system(
            { 'git', 'config', '--get', 'init.defaultBranch' },
            { text = true },
            function(result)
              coroutine.resume(co, #result.stdout > 0 and vim.trim(result.stdout) or nil)
            end
          )
          dict['head'] = coroutine.yield()
        end
        local parts = ''
        for i = 1, 4 do
          if i == 1 or (type(dict[order[i]]) == 'number' and dict[order[i]] > 0) then
            parts = ('%s %s'):format(parts, group_fmt('Git', alias[i], signs[i] .. dict[order[i]]))
          end
        end
        pieces[idx] = parts
      end)
    end,
    async = true,
    name = 'git',
    event = { 'User GitSignsUpdate', 'BufEnter' },
  }
end

local function diagnostic_info()
  return function()
    if not vim.diagnostic.is_enabled({ bufnr = 0 }) or #lsp.get_clients({ bufnr = 0 }) == 0 then
      return ''
    end
    local t = {}
    for i = 1, 3 do
      local count = #diagnostic.get(0, { severity = i })
      t[#t + 1] = ('%%#ModeLine%s#%s%%*'):format(vim.diagnostic.severity[i], count)
    end
    return (' %s'):format(table.concat(t, ' '))
  end
end

function M.diagnostic()
  for i = 1, 3 do
    local name = ('Diagnostic%s'):format(diagnostic.severity[i])
    local fg = api.nvim_get_hl(0, { name = name }).fg
    api.nvim_set_hl(0, 'ModeLine' .. diagnostic.severity[i], { fg = fg, bg = stl_bg })
  end
  return {
    stl = diagnostic_info(),
    event = { 'DiagnosticChanged', 'BufEnter', 'LspAttach' },
  }
end

function M.eol()
  local format = vim.bo.fileformat
  local icon = ""
  -- local text = ""

  if format == 'unix' then
    icon = " "
    --text = "LF"
  elseif format == 'dos' then
    icon = " "
    --text = "CRLF"
  elseif format == 'mac' then
    icon = " "
    --text = "CR"
  end
  return {
    name = 'eol',
    stl = (' %s'):format(icon),
    event = { 'BufEnter' },
  }
end

function M.encoding()
  return {
    stl = (' %s'):format(vim.bo.fileencoding),
    name = 'filencode',
    event = { 'BufEnter' },
  }
end

---@private
local function binary_search(tbl, line)
  local left = 1
  local right = #tbl
  local mid = 0

  while true do
    mid = bit.rshift(left + right, 1)
    if not tbl[mid] then
      return
    end

    local range = tbl[mid].range or tbl[mid].location.range
    if not range then
      return
    end

    if line >= range.start.line and line <= range['end'].line then
      return mid
    elseif line < range.start.line then
      right = mid - 1
    else
      left = mid + 1
    end
    if left > right then
      return
    end
  end
end

function M.doucment_symbol()
  return {
    stl = function()
      return coroutine.create(function(pieces, idx)
        local params = { textDocument = lsp.util.make_text_document_params() }
        local co = coroutine.running()
        vim.lsp.buf_request(0, 'textDocument/documentSymbol', params, function(err, result, ctx)
          if err or not api.nvim_buf_is_loaded(ctx.bufnr) then
            return
          end
          local lnum = api.nvim_win_get_cursor(0)[1]
          local mid = binary_search(result, lnum)
          if not mid then
            return
          end
          coroutine.resume(co, result[mid])
        end)
        local data = coroutine.yield()
        pieces[idx] = (' %s '):format(data.name)
      end)
    end,
    async = true,
    name = 'DocumentSymbol',
    event = { 'CursorHold' },
    attr = stl_attr('Symbol'),
  }
end

return M
