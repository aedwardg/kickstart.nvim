-- Rex integration.
--
-- When Neovim runs in a Rex pane, it listens on a socket named after that
-- pane. Rex actions (~/.config/rex/file_refs.lua) use the socket to find the
-- Neovim in a tab and open files in it, so `ctrl+b o` in a pane showing
-- `app/models/order.rb:142` lands here at line 142.
local M = {}

-- Must match SOCKET_DIR in ~/.config/rex/file_refs.lua.
M.socket_dir = vim.fn.expand '~/.cache/rex-nvim'

function M.setup()
  local block = vim.env.REX_BLOCK
  if not block or block == '' then
    return
  end
  vim.fn.mkdir(M.socket_dir, 'p', tonumber('700', 8))
  local path = M.socket_dir .. '/' .. (block:gsub('^block:', '')) .. '.sock'

  if vim.uv.fs_stat(path) then
    -- Another Neovim in this pane (one started from :terminal, say) already
    -- answers on the socket, so leave it be.
    local ok, chan = pcall(vim.fn.sockconnect, 'pipe', path, { rpc = true })
    if ok and chan > 0 then
      vim.fn.chanclose(chan)
      return
    end
    vim.uv.fs_unlink(path) -- left behind by a Neovim that crashed
  end
  pcall(vim.fn.serverstart, path)
end

-- The window to open files in: the current one if it shows a normal buffer,
-- otherwise the first one in the tab that does (not neo-tree, quickfix, ...).
local function editing_window()
  local function normal(win)
    local buf = vim.api.nvim_win_get_buf(win)
    return vim.bo[buf].buftype == '' and vim.api.nvim_win_get_config(win).relative == ''
  end
  local current = vim.api.nvim_get_current_win()
  if normal(current) then
    return current
  end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if normal(win) then
      return win
    end
  end
  return current
end

-- Open item.filename at item.lnum and item.col, both optional.
local function jump(item)
  vim.api.nvim_set_current_win(editing_window())
  vim.cmd.stopinsert()
  vim.cmd "normal! m'" -- so <C-o> comes back here
  local ok, err = pcall(vim.cmd, 'edit ' .. vim.fn.fnameescape(item.filename))
  if not ok then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end
  if item.lnum then
    local lnum = math.min(item.lnum, vim.api.nvim_buf_line_count(0))
    pcall(vim.api.nvim_win_set_cursor, 0, { lnum, math.max((item.col or 1) - 1, 0) })
    vim.cmd 'normal! zvzz' -- open folds around the line and center it
  end
end

-- Called by Rex: open a file. lnum and col are 0 when not known.
function M.open(filename, lnum, col)
  vim.schedule(function()
    jump {
      filename = filename,
      lnum = lnum > 0 and lnum or nil,
      col = col > 0 and col or nil,
    }
  end)
  return ''
end

-- Called by Rex: pick one of the file references it found in a pane.
-- json_path holds a list of { filename, path, lnum?, col?, text }, newest
-- first, and is deleted once read. With quit_on_cancel, Neovim quits when the
-- picker closes without opening anything, which closes the pane Rex opened
-- just for it.
function M.pick(json_path, quit_on_cancel)
  vim.schedule(function()
    local ok, items = pcall(function()
      return vim.json.decode(table.concat(vim.fn.readfile(json_path), '\n'), { luanil = { object = true } })
    end)
    os.remove(json_path)
    if not ok or type(items) ~= 'table' or #items == 0 then
      vim.notify('Rex: could not read file references from ' .. json_path, vim.log.levels.ERROR)
      return
    end

    local pickers = require 'telescope.pickers'
    local finders = require 'telescope.finders'
    local conf = require('telescope.config').values
    local actions = require 'telescope.actions'
    local action_state = require 'telescope.actions.state'

    pickers
      .new({}, {
        prompt_title = 'Open File Reference',
        finder = finders.new_table {
          results = items,
          entry_maker = function(item)
            local where = vim.fn.fnamemodify(item.filename, ':~:.') .. (item.lnum and (':' .. item.lnum) or '')
            return {
              value = item,
              display = where .. '  ' .. vim.trim(item.text),
              ordinal = where .. ' ' .. item.text,
              -- For the previewer and Telescope's own split and tab actions.
              filename = item.filename,
              lnum = item.lnum or 1,
              col = item.col or 1,
            }
          end,
        },
        sorter = conf.generic_sorter {},
        previewer = conf.qflist_previewer {},
        attach_mappings = function(prompt_bufnr)
          actions.select_default:replace(function()
            local entry = action_state.get_selected_entry()
            actions.close(prompt_bufnr)
            if entry then
              jump(entry.value)
            end
          end)
          if quit_on_cancel then
            vim.api.nvim_create_autocmd('BufWipeout', {
              buffer = prompt_bufnr,
              once = true,
              callback = vim.schedule_wrap(function()
                -- Opened nothing (every buffer is still the empty startup one).
                for _, buf in ipairs(vim.api.nvim_list_bufs()) do
                  if vim.bo[buf].buflisted and vim.api.nvim_buf_get_name(buf) ~= '' then
                    return
                  end
                end
                vim.cmd 'qall'
              end),
            })
          end
          return true
        end,
      })
      :find()
  end)
  return ''
end

return M
