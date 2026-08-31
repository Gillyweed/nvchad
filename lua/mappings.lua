require "nvchad.mappings"

-- add yours here

local map = vim.keymap.set

map("n", ";", ":", { desc = "CMD enter command mode" })

-- replace <C-n> nvim-tree toggle with <leader>n
map("n", "<leader>n", "<cmd>NvimTreeToggle<CR>", { desc = "Toggle nvimtree" })

-- toggle focus between nvimtree and the buffer
map("n", "<leader>e", function()
  local nvimtree = require("nvim-tree.api")
  local current_buf = vim.api.nvim_get_current_buf()
  if vim.bo[current_buf].filetype == "NvimTree" then
    vim.cmd("wincmd p")
  else
    nvimtree.tree.focus()
  end
end, { desc = "Toggle focus between nvimtree and buffer" })
map("i", "jk", "<ESC>")

map({ "n", "i", "v" }, "<C-s>", "<cmd> w <cr>")
map("n", "H", "^", { desc = "Jump to line start" })
map("n", "L", "$", { desc = "Jump to line end" })
map("o", "H", "^")
map("o", "L", "$")


map("n", "<Esc>", "<cmd>nohlsearch<CR>", { desc = "Clear highlights on search when pressing <Esc>" })
map('v', 'J', ":m '>+1<CR>gv=gv")
map('v', 'K', ":m '<-2<CR>gv=gv")

map("t", "<C-x>", "<C-\\><C-n>", { desc = "Exit terminal mode" })

-- show git blame for the current line in a readable popup (author, relative
-- time + date, and commit summary -- no hash)
local function relative_time(t)
  local diff = os.difftime(os.time(), t)
  local units = {
    { 31536000, "year" },
    { 2592000, "month" },
    { 604800, "week" },
    { 86400, "day" },
    { 3600, "hour" },
    { 60, "minute" },
  }
  for _, u in ipairs(units) do
    if diff >= u[1] then
      local n = math.floor(diff / u[1])
      return n .. " " .. u[2] .. (n > 1 and "s" or "") .. " ago"
    end
  end
  return "just now"
end

-- from a unified diff, find the hunk whose new-side range covers `target`
local function find_hunk(diff, target)
  if not target then
    return nil
  end
  local hunks, cur = {}, nil
  for _, l in ipairs(diff) do
    local ns, nc = l:match "^@@ %-%d+,?%d* %+(%d+),?(%d*) @@"
    if ns then
      ns = tonumber(ns)
      nc = nc ~= "" and tonumber(nc) or 1
      cur = { lo = ns, hi = ns + math.max(nc, 1) - 1, body = {} }
      hunks[#hunks + 1] = cur
    elseif cur then
      local c = l:sub(1, 1)
      if c == " " or c == "+" or c == "-" then
        cur.body[#cur.body + 1] = l
      end
    end
  end
  for _, h in ipairs(hunks) do
    if target >= h.lo and target <= h.hi then
      return h
    end
  end
  return nil
end

-- keep only the diff body lines within `ctx` new-file lines of `target`
local function trim_around(hunk, target, ctx)
  local out, newln = {}, hunk.lo
  for _, l in ipairs(hunk.body) do
    if newln >= target - ctx and newln <= target + ctx then
      out[#out + 1] = l
    end
    if l:sub(1, 1) ~= "-" then -- '-' lines don't exist on the new side
      newln = newln + 1
    end
  end
  return out
end

-- open a focused, scrollable float; <Esc> or q closes it
local function open_blame_float(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "diff"
  vim.bo[buf].modifiable = false

  local width, height = 0, #lines
  for _, l in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(l))
  end
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "cursor",
    row = 1,
    col = 0,
    width = math.min(width + 1, vim.o.columns - 4),
    height = math.min(height, vim.o.lines - 6),
    border = "rounded",
    style = "minimal",
  })
  vim.wo[win].wrap = false
  for _, key in ipairs { "<Esc>", "q" } do
    map("n", key, "<cmd>close<CR>", { buffer = buf, nowait = true })
  end
end

map("n", "<leader>gb", function()
  local file = vim.api.nvim_buf_get_name(0)
  if file == "" then
    return
  end
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local dir = vim.fn.fnamemodify(file, ":h")
  local out = vim.fn.systemlist {
    "git", "-C", dir, "blame", "-L", lnum .. "," .. lnum,
    "--line-porcelain", "--", file,
  }
  if vim.v.shell_error ~= 0 then
    vim.notify("git blame failed", vim.log.levels.WARN)
    return
  end

  local sha, orig = out[1]:match "^(%x+)%s+(%d+)"
  orig = tonumber(orig)
  if sha and sha:match "^0+$" then
    open_blame_float { "Not committed yet" }
    return
  end

  local info = {}
  for _, line in ipairs(out) do
    if line:sub(1, 1) == "\t" then
      break
    end
    local key, val = line:match "^([%w%-]+) (.*)$"
    if key == "author" then
      info.author = val
    elseif key == "author-time" then
      info.time = tonumber(val)
    elseif key == "summary" then
      info.summary = val
    end
  end

  local header = info.author or "Unknown"
  if info.time then
    header = header .. " • " .. relative_time(info.time) .. " (" .. os.date("%Y-%m-%d", info.time) .. ")"
  end

  local lines = { header, "", info.summary or "" }
  local diff = vim.fn.systemlist {
    "git", "-C", dir, "show", "--format=", "--no-color", sha, "--", file,
  }
  if vim.v.shell_error == 0 and #diff > 0 then
    local hunk = find_hunk(diff, orig)
    local body = hunk and trim_around(hunk, orig, 3) or diff
    table.insert(lines, "")
    vim.list_extend(lines, body)
  end
  open_blame_float(lines)
end, { desc = "Git blame (popup)" })

-- resolve this branch's base (origin's default branch, then common names) and
-- the merge-base commit; returns root, base, mergebase or nil on failure.
-- pass quiet=true to suppress warnings (used by the always-on sign refresh)
local function git_base(quiet)
  local root = vim.fn.systemlist({ "git", "rev-parse", "--show-toplevel" })[1]
  if vim.v.shell_error ~= 0 then
    if not quiet then
      vim.notify("Not in a git repo", vim.log.levels.WARN)
    end
    return
  end

  local function rev_exists(rev)
    vim.fn.system { "git", "-C", root, "rev-parse", "--verify", "--quiet", rev }
    return vim.v.shell_error == 0
  end

  -- prefer origin's default branch, then fall back to common names
  local base
  local origin_head = vim.fn.systemlist { "git", "-C", root, "symbolic-ref", "--quiet", "refs/remotes/origin/HEAD" }
  if vim.v.shell_error == 0 and origin_head[1] then
    base = origin_head[1]:gsub("^refs/remotes/", "")
  end
  if not base then
    for _, b in ipairs { "origin/main", "origin/master", "main", "master" } do
      if rev_exists(b) then
        base = b
        break
      end
    end
  end
  if not base then
    if not quiet then
      vim.notify("Could not determine a base branch", vim.log.levels.WARN)
    end
    return
  end

  -- the merge-base so we only consider what this branch introduced
  local mb = vim.fn.systemlist({ "git", "-C", root, "merge-base", "HEAD", base })[1]
  if vim.v.shell_error ~= 0 or not mb or mb == "" then
    mb = base
  end

  return root, base, mb
end

-- diff the current buffer's file against the branch base (merge-base) and parse
-- the hunks. returns a list of hunks, each: { target, adds = {...}, dels = {...} }
-- where line numbers are new-side (they line up with the working-tree buffer)
-- and `target` is the first actually-changed line, not the hunk's context start.
-- this covers committed + staged + unstaged changes, unlike gitsigns (which
-- only diffs against the index). pass quiet=true to silence git_base warnings
local function branch_hunks(buf, quiet)
  local root, _, mb = git_base(quiet)
  if not root then
    return
  end

  local file = vim.api.nvim_buf_get_name(buf)
  if file == "" then
    return
  end

  local diff = vim.fn.systemlist { "git", "-C", root, "diff", "--no-color", mb, "--", file }
  local hunks, cur, new_line = {}, nil, nil
  for _, l in ipairs(diff) do
    -- "@@ -a,b +c,d @@": c is the new-side start line of the hunk
    local c = l:match "^@@ %-%d[%d,]* %+(%d+)"
    if c then
      cur = { target = nil, adds = {}, dels = {} }
      hunks[#hunks + 1] = cur
      new_line = tonumber(c)
    elseif cur then
      -- header lines (---/+++) appear before the first @@, so cur is nil there
      local kind = l:sub(1, 1)
      if kind == "+" then
        cur.adds[#cur.adds + 1] = new_line
        cur.target = cur.target or new_line
        new_line = new_line + 1
      elseif kind == "-" then
        cur.dels[#cur.dels + 1] = new_line
        cur.target = cur.target or new_line
        -- deletions don't advance the new-side counter
      elseif kind == " " then
        new_line = new_line + 1
      end
    end
  end
  return hunks
end

-- jump to the next/previous branch-base change in the current buffer, wrapping
-- around at the ends and centering the landed line
local function nav_branch_hunk(direction)
  local hunks = branch_hunks(0)
  if not hunks then
    return
  end
  if #hunks == 0 then
    vim.notify("No branch changes in this buffer", vim.log.levels.INFO)
    return
  end

  local cur = vim.api.nvim_win_get_cursor(0)[1]
  local target
  if direction == "next" then
    for _, h in ipairs(hunks) do
      if h.target > cur then
        target = h.target
        break
      end
    end
    target = target or hunks[1].target -- wrap to first
  else
    for i = #hunks, 1, -1 do
      if hunks[i].target < cur then
        target = hunks[i].target
        break
      end
    end
    target = target or hunks[#hunks].target -- wrap to last
  end

  vim.api.nvim_win_set_cursor(0, { math.max(target, 1), 0 })
  vim.cmd "normal! zz"
end

map("n", "<leader>fg", function()
  nav_branch_hunk("next")
end, { desc = "Find next branch change" })

map("n", "<leader>Fg", function()
  nav_branch_hunk("prev")
end, { desc = "Find previous branch change" })

-- sign-column markers for branch-base changes, refreshed on buffer enter/save.
-- reuses gitsigns' highlight groups so they match the editor theme
local branch_sign_ns = vim.api.nvim_create_namespace "branch_base_signs"
local function refresh_branch_signs(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" then
    return
  end

  vim.api.nvim_buf_clear_namespace(buf, branch_sign_ns, 0, -1)
  local hunks = branch_hunks(buf, true)
  if not hunks then
    return
  end

  local last = vim.api.nvim_buf_line_count(buf)
  local function place(line, text, hl)
    line = math.min(math.max(line, 1), last)
    pcall(vim.api.nvim_buf_set_extmark, buf, branch_sign_ns, line - 1, 0, {
      sign_text = text,
      sign_hl_group = hl,
    })
  end

  for _, h in ipairs(hunks) do
    if #h.adds > 0 then
      -- a hunk with both adds and dels is a modification, otherwise a pure add
      local hl = (#h.dels > 0) and "GitSignsChange" or "GitSignsAdd"
      for _, ln in ipairs(h.adds) do
        place(ln, "┃", hl)
      end
    elseif #h.dels > 0 then
      place(h.dels[1], "▁", "GitSignsDelete")
    end
  end
end

local branch_sign_grp = vim.api.nvim_create_augroup("BranchBaseSigns", { clear = true })
vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
  group = branch_sign_grp,
  callback = function(args)
    refresh_branch_signs(args.buf)
  end,
})

-- preview the diff of the hunk under the cursor (old vs new lines) inline.
-- diffs against the branch base (merge-base), so it covers committed + staged +
-- unstaged changes -- the same base <leader>fg navigates -- unlike gitsigns'
-- preview_hunk, which only sees unstaged edits vs the index
map("n", "<leader>gd", function()
  local root, base, mb = git_base()
  if not root then
    return
  end

  local file = vim.api.nvim_buf_get_name(0)
  if file == "" then
    vim.notify("No file in this buffer", vim.log.levels.WARN)
    return
  end

  local diff = vim.fn.systemlist { "git", "-C", root, "diff", "--no-color", mb, "--", file }
  local cursor = vim.api.nvim_win_get_cursor(0)[1]
  local hunk = find_hunk(diff, cursor)
  if not hunk then
    vim.notify("No branch change under the cursor", vim.log.levels.INFO)
    return
  end

  local header = string.format("@@ hunk vs %s @@", base)
  local lines = { header }
  vim.list_extend(lines, hunk.body)
  open_blame_float(lines)
end, { desc = "Git diff hunk (preview vs base)" })

-- fuzzy, previewable LSP navigation via Telescope
map("n", "<leader>fr", "<cmd>Telescope lsp_references<CR>", { desc = "Find LSP references" })
map("n", "<leader>fd", "<cmd>Telescope lsp_definitions<CR>", { desc = "Find LSP definitions" })

-- Uncommitted (working tree) changes are handled by the NvChad default
-- <leader>gt -> Telescope git_status (file list + inline diff preview).

-- preview every file changed on this branch vs its base branch (committed
-- work since the branch diverged + any uncommitted edits), with a full diff
-- preview; <CR> opens the selected file. returns true when a picker was
-- actually opened, so the startup hook below can fall back to another one
local function git_branch_changes(quiet)
  local pickers = require "telescope.pickers"
  local finders = require "telescope.finders"
  local conf = require("telescope.config").values
  local previewers = require "telescope.previewers"
  local actions = require "telescope.actions"
  local action_state = require "telescope.actions.state"

  local root, base, mb = git_base(quiet)
  if not root then
    return
  end

  local files = vim.fn.systemlist { "git", "-C", root, "diff", "--name-only", mb }
  if #files == 0 then
    if not quiet then
      vim.notify("No changes vs " .. base, vim.log.levels.INFO)
    end
    return
  end

  pickers
    .new({}, {
      prompt_title = "Branch changes vs " .. base,
      finder = finders.new_table { results = files },
      sorter = conf.generic_sorter {},
      previewer = previewers.new_termopen_previewer {
        get_command = function(entry)
          return { "git", "-C", root, "diff", mb, "--", entry.value }
        end,
      },
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local entry = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if entry then
            vim.cmd("edit " .. vim.fn.fnameescape(root .. "/" .. entry.value))
            -- land on the first change in the file rather than the top, reusing
            -- the same branch-base diff the picker preview shows
            local hunks = branch_hunks(0, true)
            if hunks and hunks[1] then
              vim.api.nvim_win_set_cursor(0, { math.max(hunks[1].target, 1), 0 })
              vim.cmd "normal! zz"
            end
          end
        end)
        return true
      end,
    })
    :find()

  return true
end

map("n", "<leader>gc", git_branch_changes, { desc = "Find branch changes (vs base)" })

-- open a picker on startup when nvim is launched without a file to edit -- either
-- bare (`nvim`) or on a directory (`nvim .`), the same two cases the old
-- nvim-tree auto-open covered. init.lua requires this file from a vim.schedule,
-- i.e. after VimEnter has already fired, so a VimEnter autocmd here would never
-- run -- the check happens inline instead, deferred one more tick so it lands on
-- top of nvdash. quiet = true keeps the branch picker silent when there's nothing
-- to show (outside a git repo, or no changes vs base); find_files takes over there
local argc = vim.fn.argc()
local dir_arg = argc == 1 and vim.fn.isdirectory(vim.fn.argv(0)) == 1 and vim.fn.argv(0) or nil
if argc == 0 or dir_arg then
  vim.schedule(function()
    -- `nvim <dir>` leaves cwd wherever the shell was, which would scope both
    -- pickers (git runs in cwd) to the wrong repo -- follow the directory first,
    -- as nvim-tree used to. no-op for the common `nvim .`
    if dir_arg then
      vim.cmd.cd(vim.fn.fnameescape(dir_arg))
    end
    if not git_branch_changes(true) then
      require("telescope.builtin").find_files()
    end
  end)
end

-- preview every file touched by the latest commit (HEAD), with a per-file diff
-- preview; <CR> opens the selected file. Mirrors <leader>gc but scoped to the
-- most recent commit (our workflow keeps one commit per branch)
local function git_latest_commit_changes()
  local pickers = require "telescope.pickers"
  local finders = require "telescope.finders"
  local conf = require("telescope.config").values
  local previewers = require "telescope.previewers"
  local actions = require "telescope.actions"
  local action_state = require "telescope.actions.state"

  local root = vim.fn.systemlist({ "git", "rev-parse", "--show-toplevel" })[1]
  if vim.v.shell_error ~= 0 then
    vim.notify("Not in a git repo", vim.log.levels.WARN)
    return
  end

  local subject = vim.fn.systemlist({ "git", "-C", root, "log", "-1", "--format=%h %s" })[1]

  local files = vim.fn.systemlist {
    "git", "-C", root, "show", "--name-only", "--format=", "--no-color", "HEAD",
  }
  if #files == 0 then
    vim.notify("Latest commit has no file changes", vim.log.levels.INFO)
    return
  end

  pickers
    .new({}, {
      prompt_title = "Latest commit: " .. (subject or "HEAD"),
      finder = finders.new_table { results = files },
      sorter = conf.generic_sorter {},
      previewer = previewers.new_termopen_previewer {
        get_command = function(entry)
          -- colorize the diff; pipe through delta for language-aware syntax
          -- highlighting when it's installed, otherwise use git's own colors
          local show = string.format(
            "git -C %s show --color=always HEAD -- %s",
            vim.fn.shellescape(root),
            vim.fn.shellescape(entry.value)
          )
          if vim.fn.executable "delta" == 1 then
            show = show .. " | delta --paging=never"
          end
          return { "sh", "-c", show }
        end,
      },
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local entry = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if entry then
            vim.cmd("edit " .. vim.fn.fnameescape(root .. "/" .. entry.value))
          end
        end)
        return true
      end,
    })
    :find()
end

map("n", "<leader>gl", git_latest_commit_changes, { desc = "Find latest commit changes" })

-- open lazygit (TUI for stage/commit/rebase/push) in a snacks float
map("n", "<leader>gg", function()
  require("snacks").lazygit()
end, { desc = "Open lazygit" })

-- manually format the current buffer / selection (conform, falling back to LSP)
map({ "n", "v" }, "<leader>mp", function()
  require("conform").format { lsp_fallback = true, timeout_ms = 10000 }
end, { desc = "Format buffer" })

-- d and c deletes to the blackhole register
map("n", "d", '"_d')
map("v", "d", '"_d')
map("n", "c", '"_c')
map("v", "c", '"_c')

-- x as cut (sends to main register)
map("n", "x", '"+d')
map("v", "x", '"+d')

-- xx to cut a whole line
map("n", "xx", '"+dd')

-- X to cut from cursor to end of line
map("n", "X", '"+D')

vim.keymap.set("x", "<", "<gv")
vim.keymap.set("x", ">", ">gv")

-- keep cursor in the middle of the screen when jumping
vim.keymap.set('n', '<C-d>', '<C-d>zz')
vim.keymap.set('n', '<C-u>', '<C-u>zz')

vim.keymap.set('n', 'n', 'nzzzv')
vim.keymap.set('n', 'N', 'Nvvvv')

-- Resize splits
map("n", "<C-Up>", "<cmd>resize +2<CR>", { desc = "Resize split up" })
map("n", "<C-Down>", "<cmd>resize -2<CR>", { desc = "Resize split down" })
map("n", "<C-Left>", "<cmd>vertical resize -2<CR>", { desc = "Resize split left" })
map("n", "<C-Right>", "<cmd>vertical resize +2<CR>", { desc = "Resize split right" })

map("n", "<leader>x", function()
  -- Close the current buffer
  require("nvchad.tabufline").close_buffer()

  -- Check if only nvim-tree and/or empty buffers remain
  vim.defer_fn(function()
    -- Don't quit if multiple tabs
    if #vim.api.nvim_list_tabpages() > 1 then
      return
    end

    local wins = vim.api.nvim_list_wins()
    local has_real_buffer = false

    for _, win in ipairs(wins) do
      local buf = vim.api.nvim_win_get_buf(win)
      local ft = vim.bo[buf].filetype
      local bufname = vim.api.nvim_buf_get_name(buf)

      -- Skip nvim-tree and empty unnamed buffers
      if ft ~= "NvimTree" and (bufname ~= "" or vim.bo[buf].modified) then
        has_real_buffer = true
        break
      end
    end

    -- Quit if no real buffers remain (only nvim-tree and/or empty buffers)
    if not has_real_buffer then
      vim.cmd("quit")
    end
  end, 50)
end, { desc = "Close buffer and quit if last" })
