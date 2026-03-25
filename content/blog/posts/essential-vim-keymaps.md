---
date: '2025-12-01'
draft: false
title: 'Boost Your Productivity With These Essential Vim Keymaps'
---
After years of modifying my Neovim configuration, I've settled on a set of keymaps that I simply can't live without. These aren't flashy or complex but they're practical quality-of-life (qol) improvements that fix some of Vim's rough edges and make daily editing smoother.

*Note: These keymaps are written in Lua. If you're using Vim with vimscript, you can easily convert these using the equivalent nnoremap, inoremap, vnoremap, and xnoremap commands.*

## 1\. Move Lines Like a Pro

One of the most satisfying operations is moving lines up and down without cutting and pasting. These keymaps make it effortless:

```lua
-- Normal mode
vim.keymap.set('n', '<A-j>', "<cmd>execute 'move .+' . v:count1<cr>==", { desc = 'Move Down' })
vim.keymap.set('n', '<A-k>', "<cmd>execute 'move .-' . (v:count1 + 1)<cr>==", { desc = 'Move Up' })

-- Insert mode
vim.keymap.set('i', '<A-j>', '<esc><cmd>m .+1<cr>==gi', { desc = 'Move Down' })
vim.keymap.set('i', '<A-k>', '<esc><cmd>m .-2<cr>==gi', { desc = 'Move Up' })

-- Visual mode
vim.keymap.set('v', '<A-j>', ":<C-u>execute \"'<,'>move '>+\" . v:count1<cr>gv=gv", { desc = 'Move Down' })
vim.keymap.set('v', '<A-k>', ":<C-u>execute \"'<,'>move '<-\" . (v:count1 + 1)<cr>gv=gv", { desc = 'Move Up' })
```

*Use* `Alt+j` *and* `Alt+k` *to move lines (or visual selections) up and down. The magic here is that it works in all three modes (normal, insert, and visual) and automatically re-indents your code. Even better, it respects counts, so* `3<A-j>` *moves the line down three positions.*

## 2\. Clear Search Highlights Instantly

Nothing clutters your screen like lingering search highlights after you're done searching:

```lua
vim.keymap.set('n', '<Esc>', '<cmd>nohlsearch<CR>')
```

*Press* `Esc` *to clear search highlights without affecting anything else. It's muscle memory that saves you from typing* `:noh` *dozens of times a day.*

## 3\. Escape Terminal Mode Sanely

Vim's terminal mode is powerful, but getting out of it with the default `<C-\><C-n>` is awkward:

```lua
vim.keymap.set('t', '<Esc><Esc>', '<C-\\><C-n>', { desc = 'Exit terminal mode' })
```

*Double* `Esc` *to exit terminal mode feels natural and consistent with other modes.*

## 4\. Paste Without Losing Your Clipboard

This one solves a problem that frustrates every Vim beginner: when you paste over a visual selection, Vim yanks the deleted text into your default register, overwriting what you wanted to paste again.

```lua
vim.keymap.set('x', '<leader>p', '"_dP')
```

*Use* `<leader>p` *in visual mode to paste without losing your clipboard contents. It deletes the selection to the black hole register (*`"_`*) before pasting, so you can paste the same thing multiple times.*

## 5\. Copy to System Clipboard

Working with the system clipboard in Vim can be clunky. This makes it trivial:

```lua
vim.keymap.set('n', '<leader>y', '"+y')
vim.keymap.set('v', '<leader>y', '"+y')
```

`<leader>y` *copies to the system clipboard (*`+` *register) instead of Vim's internal registers.*

## 6\. Delete Without Affecting Clipboard

Sometimes you want to delete text without storing it anywhere:

```lua
vim.keymap.set('n', '<leader>d', '"_d')
vim.keymap.set('v', '<leader>d', '"_d')
```

`<leader>d` *deletes to the black hole register, keeping your clipboard intact. Perfect for removing text you don't need to paste elsewhere.*

## 7\. Quick File Navigation with Netrw

Vim's built-in file explorer (netrw) is surprisingly powerful once you have quick access to it:

```lua
vim.keymap.set('n', '<leader>e', ':Ex<cr>', { desc = 'Open netrw' })
```

`<leader>e` *instantly opens netrw in the current window, letting you navigate your project structure without reaching for a mouse or a separate file tree plugin. It's lightweight, always available, and surprisingly capable once you learn the basics (- to go up a directory, % to create a file, d to create a directory).*

## Credit Where Credit's Due

I first fell down the Vim rabbit hole thanks to ThePrimeagen's excellent video "0 to LSP : Neovim RC From Scratch". If you're building your config from scratch or looking to understand the fundamentals, it's an invaluable resource. Many of these keymaps are inspired by patterns and principles I learned from his content and the broader Neovim community.

<!-- https://gohugo.io/shortcodes/ -->
{{< youtube w7i4amO_zaE >}}

The beauty of Vim is that everyone's config evolves differently based on their workflow. These keymaps work for me, but your mileage may vary. The important thing is understanding why each mapping exists so you can adapt them to your needs.
