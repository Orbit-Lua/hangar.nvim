-- Gates Tree-sitter highlighting from saved state. One owned `FileType` group
-- stops Tree-sitter in each buffer whose parser language is disabled. The stop
-- is scheduled, so it runs after the consumer's own `FileType` handler starts
-- Tree-sitter. Hangar restarts Tree-sitter only in buffers that it stopped, so
-- it never starts Tree-sitter where the consumer did not.
local M = {}

local GROUP = "HangarTreesitter"

---Buffers that Hangar stopped, by parser language.
---@type table<string, table<integer, true>>
local stopped = {}

---@return boolean
local function active()
  local config = require("hangar.config")
  return config.configured() and config.get().integrations.treesitter == true
end

---@param buf integer
---@return string?
local function language(buf)
  return vim.treesitter.language.get_lang(vim.bo[buf].filetype)
end

---@param lang string?
---@return boolean
local function disabled(lang)
  return lang ~= nil and not require("hangar.state").is_enabled("parser", lang)
end

---Stop Tree-sitter in a buffer where it runs, and record the buffer.
---@param buf integer
---@param lang string
local function stop(buf, lang)
  if
    not vim.api.nvim_buf_is_valid(buf)
    or not vim.treesitter.highlighter.active[buf]
  then
    return
  end
  vim.treesitter.stop(buf)
  stopped[lang] = stopped[lang] or {}
  stopped[lang][buf] = true
end

---Stop Tree-sitter in the open buffers of a language.
---@param lang string
function M.disable(lang)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if language(buf) == lang then
      stop(buf, lang)
    end
  end
end

---Restart Tree-sitter in the buffers of a language that Hangar stopped and
---that still use that language.
---@param lang string
function M.enable(lang)
  for buf in pairs(stopped[lang] or {}) do
    if vim.api.nvim_buf_is_valid(buf) and language(buf) == lang then
      pcall(vim.treesitter.start, buf, lang)
    end
  end
  stopped[lang] = nil
end

---Create the `FileType` group and bring open buffers in line with saved state
---and options. With the integration off, restart the recorded buffers.
function M.setup()
  for lang in pairs(vim.deepcopy(stopped)) do
    if not active() or not disabled(lang) then
      M.enable(lang)
    end
  end
  if not active() then
    pcall(vim.api.nvim_del_augroup_by_name, GROUP)
    return
  end

  for name, enabled in pairs(require("hangar.state").get().parser or {}) do
    if enabled == false then
      M.disable(name)
    end
  end
  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup(GROUP, { clear = true }),
    desc = "Stop Tree-sitter for parsers that Hangar disables",
    callback = function(args)
      local buf = args.buf
      local lang = vim.treesitter.language.get_lang(args.match)
      if not disabled(lang) then
        return
      end
      vim.schedule(function()
        -- The buffer can change its filetype before the stop runs.
        if
          vim.api.nvim_buf_is_valid(buf)
          and language(buf) == lang
          and disabled(lang)
        then
          stop(buf, lang)
        end
      end)
    end,
  })
end

return M
