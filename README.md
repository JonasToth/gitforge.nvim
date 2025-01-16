# gitforge.nvim - Issues, PRs, CI/CD

This plugin aims to provide integrated access to various Git Forges for your daily development
tasks - working with issues, working with PRs and checking CI/CD pipelines.

> [!WARNING]
> This plugin is in an early development state. Things may not work, they are clumsy and may break
> randomly after an update.
> Please keep this in mind.

Read more about the goals and development milestones under [development resources](development_resources/README.md).

## Installation

**lazy.nvim**
<detail>
```lua
return {
    "JonasToth/gitforge.nvim",
    opts = {},
    event = "VeryLazy",
}
```
</detail>

Please call `:checkhealth gitforge` to see if any issues are detected by the plugin.

## Usage

> [!NOTE]
> The commands of this plugin execute a CLI tool in the background. Its behavior depends on the working
> directory of `nvim`.
> ```bash
> $ cd $MY_GIT_REPOSITORY
> $ nvim
> > # Usage here will perform commands as if calling e.g. 'gh issue list' directly
> ```
> You can change your working directory in `nvim` with the `:cd path/to/new/directory` command.

## Status

### General Capabilities

- [ ] Project Specific configuration to use different backends for different repositories
- [ ] Proper Commands for more efficient lazy loading

### Issues

- [ ] Github (using `gh` cli)
    - [x] Listing Issues via `telescope.nvim`
    - [x] Creating an issue
    - [x] Editing a single issue
    - [x] Commenting on an issue
- [ ] GitLab (using `glab` cli)
    - [ ] Listing Issues via `telescope.nvim`
    - [ ] Creating an issue
    - [ ] Editing a single issue
    - [ ] Commenting on an issue

### Pull Requests

No work has been done.

### CI/Commands

No work has been done.
