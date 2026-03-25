---
date: '2025-12-01'
draft: false
title: 'Best Development Environment/Workflow'
---
**People often ask me: “What’s the best tech stack?” or “Why Neovim over VSCode?”**

The truth is, there’s no universal “best” - only what works best for you.

My journey: Windows with Notepad++ → Sublime → VSCode (where I was comfortable for years) → Linux + Neovim(best decision I made).

Then the real exploration began. I've tried Debian-based distros, RHEL/Fedora, CentOS/Rocky, Arch, Void, OpenSUSE, BSDs, macOS, and NixOS. Window managers and DEs: i3, awesomewm, bspwm, dwm, Hyprland, niri, GNOME, KDE, Cinnamon, MATE, XFCE.

Terminal emulators? Alacritty, kitty, ghostty, Wezterm, st, foot, GNOME Terminal, Konsole, Terminator, and more. I landed on Alacritty - not because it has the most features, but because it's minimal, patchable in Rust, and plays perfectly with tmux.

**My current stack:**

* **NixOS** - reproducible, declarative system configuration
    
* **home-manager** - version-controlled dotfiles and tool management
    
* **Nix Flakes** - reproducible, declarative dev environments
    
* **niri** - Wayland compositor that fits my workflow
    
* **Alacritty** - fast, minimal, hackable terminal
    
* **tmux** - session management and window splitting
    
* **fzf** - fuzzy search
    
* **Neovim** - custom config built from scratch for 0.11+
    

I recently rewrote my Neovim config using native LSP instead of Mason or lsp-config. Custom keybinds, handpicked plugins, autocmds. Every detail configured exactly how I think and work. It took weeks.

Was it worth it?

Absolutely.

When I open my editor now, I enter a flow state. Not because this stack is "objectively better" than VSCode or any other setup. It's because every keystroke, every command, every behavior is exactly what I need. No friction. No context switching. Just code.

Can I work in other environments? Of course. But there's a difference between *working* and *thriving*.

The hours spent experimenting weren't wasted - they were an investment in understanding exactly how I work best. Trying 10+ terminals taught me what matters to me (patchability, minimalism, tmux compatibility). Testing countless window managers showed me how I think about screen space. Rebuilding my Neovim config from scratch forced me to understand every piece of my workflow.

Every developer's optimal setup is different. The key is being willing to experiment until you find yours.
