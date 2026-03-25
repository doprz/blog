---
date: '2026-01-05'
draft: false
title: 'Managing Multiple Git Configurations'
---
If you're like most developers, you probably work on multiple projects across different contexts. Maybe you contribute to open source projects with your personal email, work on company projects with your work email, and maintain client projects with yet another identity. Manually switching git configurations between projects is tedious and error-prone. Fortunately, Git has a powerful feature that solves this problem elegantly: conditional includes with `includeIf`.

## The Problem

Consider this common scenario: You've just finished committing some personal project code, then switch to your work repository and make a commit. Hours later, you realize with horror that your personal email is now in your company's git history. This can happen especially as development setups and projects increase in complexity over time. On-call all nighters don't help either and it's an easy mistake to make.

The traditional solution involves manually running `git config user.email` every time you switch contexts, but this is fragile and easy to forget.

## The Solution: Conditional Includes

Git's [`includeIf` directive](https://git-scm.com/docs/git-config#_conditional_includes) allows you to automatically load different configuration files based on the repository's location. This means you can set up your git config once and never worry about it again.

## How It Works

The basic syntax in your global `~/.gitconfig` file looks like this:

```ini
[includeIf "gitdir:~/work/"]
    path = ~/.gitconfig-work

[includeIf "gitdir:~/personal/"]
    path = ~/.gitconfig-personal
```

When you run a git command, Git checks the current repository's location against these patterns. If there's a match, it loads the additional configuration file specified in the `path` directive.

## Setting It Up

Let's walk through a complete setup for managing work and personal projects.

### Step 1: Organize Your Repositories

First, organize your repositories by context. For example:

```
~/work/          # All work-related repositories
~/personal/      # Personal projects
~/clients/       # Client projects
```

### Step 2: Create Separate Config Files

Create a git configuration file for each context. For work:

```bash
# ~/.gitconfig-work
[user]
    name = Your Name
    email = you@company.com
    signingkey = WORK_GPG_KEY_ID

[commit]
    gpgsign = true
```

For personal projects:

```bash
# ~/.gitconfig-personal
[user]
    name = Your Name
    email = you@personal.com
    signingkey = PERSONAL_GPG_KEY_ID

[commit]
    gpgsign = true
```

### Step 3: Update Your Global Config

Edit your `~/.gitconfig` to include conditional directives:

```ini
[user]
    # Fallback configuration
    name = Your Name
    email = you@personal.com

[includeIf "gitdir:~/work/"]
    path = ~/.gitconfig-work

[includeIf "gitdir:~/personal/"]
    path = ~/.gitconfig-personal

[includeIf "gitdir:~/clients/"]
    path = ~/.gitconfig-clients
```

## Important Notes About Pattern Matching

### Trailing Slashes Matter

The `gitdir` pattern must end with a forward slash to match a directory:

```ini
# Correct - matches ~/work/ and all subdirectories
[includeIf "gitdir:~/work/"]

# Wrong - won't match subdirectories properly
[includeIf "gitdir:~/work"]
```

### Case Sensitivity

On case-sensitive filesystems (Linux, macOS with case-sensitive APFS), the paths are case-sensitive. On Windows and standard macOS, they're case-insensitive.

### Wildcards

You can use `**` for more complex matching patterns:

```ini
# Match any "company-name" directory anywhere
[includeIf "gitdir:**/company-name/**"]
    path = ~/.gitconfig-company
```

## Alternative Approach: Matching by Remote URL

If you don't organize your repositories by directory, or if you work with multiple Git hosting services, you can use [`hasconfig:remote.*.url`](https://git-scm.com/docs/git-config#Documentation/git-config.txt-hasconfigremoteurl) to apply configurations based on the remote URL pattern. This is particularly useful when you use GitHub for personal projects, GitLab for work, and Codeberg for open source contributions.

### Setup by Remote URL

```ini
# ~/.gitconfig
[includeIf "hasconfig:remote.*.url:git@github.com:your-work-org/**"]
    path = ~/.gitconfig-work

[includeIf "hasconfig:remote.*.url:git@gitlab.com:company/**"]
    path = ~/.gitconfig-company

[includeIf "hasconfig:remote.*.url:https://codeberg.org/**"]
    path = ~/.gitconfig-codeberg

[includeIf "hasconfig:remote.*.url:git@bitbucket.org:*/**"]
    path = ~/.gitconfig-bitbucket

[includeIf "hasconfig:remote.*.url:git@github.com:your-personal/**"]
    path = ~/.gitconfig-personal

```

### Why This Is Useful

This approach has several advantages:

- **Flexible organization**: Your repos can live anywhere on your filesystem
- **Service-specific configs**: Apply different settings based on GitHub vs GitLab vs Codeberg
- **Organization-based**: Match specific organizations or groups within a hosting service
- **Protocol-agnostic**: Works with both SSH and HTTPS URLs

### Combining Both Approaches

You can use both `gitdir` and `hasconfig:remote.*.url` together for maximum flexibility:

```ini
[user]
    name = Your Name
    email = personal@example.com

# Directory-based rules (checked first)
[includeIf "gitdir:~/work/"]
    path = ~/.gitconfig-work

# Remote URL-based rules (useful for exceptions)
[includeIf "hasconfig:remote.*.url:git@github.com:opensource-project/**"]
    path = ~/.gitconfig-opensource
```

**Note**: The `hasconfig:remote.*.url` condition requires that the repository already has a remote configured. It won't work immediately after `git init` but will activate once you add a remote with `git remote add`.

## Advanced Use Cases

### Different SSH Keys

You can configure different SSH keys for different contexts by including SSH configuration in your conditional config files:

```ini
# ~/.gitconfig-work
[user]
    email = you@company.com

[core]
    sshCommand = ssh -i ~/.ssh/id_rsa_work
```

### URL Rewrites

Automatically use different protocols or paths:

```ini
# ~/.gitconfig-work
[url "git@github.com-work:"]
    insteadOf = git@github.com:
```

### Different Default Branches

Set different default branch names per context:

```ini
# ~/.gitconfig-personal
[init]
    defaultBranch = main

# ~/.gitconfig-work
[init]
    defaultBranch = master
```

## Pro Tip: Editing Conditional Config Files Directly

Instead of manually opening your conditional config files in an editor, you can use git's `--file` flag to edit them directly:

```bash
# Edit your work config
git config --file=~/.gitconfig-work user.email "newemail@company.com"

# Add a new setting to your personal config
git config --file=~/.gitconfig-personal core.editor "vim"

# List all settings in a specific config file
git config --file=~/.gitconfig-work --list
```

This is especially handy when you can't remember the exact path to your config files or want to quickly update a setting without opening an editor.

## Verifying Your Configuration

To check which configuration is being used in a repository, run:

```bash
git config --list --show-origin
```

This shows each configuration value and which file it comes from. You should see values from your conditional config file for repositories in the matching directories.

To test a specific value:

```bash
git config --get user.email
```

## Troubleshooting

If your conditional configuration isn't working:

1. **Check for typos** in the `gitdir` path, especially the trailing slash
2. **Use absolute paths** or `~` for home directory, not relative paths
3. **Verify file permissions** on your config files
4. **Check the order** - later includes override earlier ones
5. **Remember** that `includeIf` only works in the global config file, not in repository-local configs

## Why This Matters

Beyond just getting the right email in commits, conditional configurations enable:

- **Security**: Use different GPG keys for signing commits in different contexts
- **Compliance**: Ensure company policies are followed automatically in work repositories
- **Productivity**: Eliminate context-switching friction and mental overhead
- **Reliability**: Prevent embarrassing mistakes like using personal credentials in company code

## Further Reading

For more details on conditional includes and all available options, check out the [official Git documentation on conditional includes](https://git-scm.com/docs/git-config#_conditional_includes). The docs cover additional conditions like `onbranch` that can provide even more granular control.

## Conclusion

Git's `includeIf` feature is a simple but powerful tool that saves time and prevents mistakes. By spending a few minutes setting up conditional configurations, you can work seamlessly across different projects and contexts without ever thinking about your git configuration again.

The next time you clone a new repository, it will automatically pick up the right configuration based on where you put it. That's the kind of automation that makes development just a little bit smoother.
