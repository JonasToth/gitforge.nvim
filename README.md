# gitforge.nvim - Issues, PRs, CI/CD

- list, comment and change issues on GitLab and Github
- pin relevant issues for you and have them available without searching for them

> [!WARNING]
> This plugin is in an early development state. Things may not work, they are clumsy and may break
> randomly after an update.
> Please keep this in mind.

This plugin aims to provide integrated access to various Git Forges for your daily development
tasks - working with issues, working with PRs and checking CI/CD pipelines.
Its goal is being a workhorse plugin that is reliable and stable.

You can read more about the goals and development milestones under [development resources](development_resources/README.md).

## Installation

**[lazy.nvim](https://github.com/folke/lazy.nvim)**
<details>

```lua
local ia = "gitforge.issue_actions"
return {
    "JonasToth/gitforge.nvim",
    version = "*",
    dependencies = {
        { "nvim-telescope/telescope.nvim" },
        { "pysan3/pathlib.nvim" },
    },
    cmd = { "GForgeViewIssue", "GForgeListIssues", "GForgeOpenedIssues", "GForgePinnedIssues", "GForgeCreateIssue" },
    keys = {
        { "<leader>gv", "<cmd>GForgeViewIssue<CR>",    desc = "View an issue" },
        { "<leader>gn", "<cmd>GForgeCreateIssue<CR>",  desc = "Create a new issue" },
        { "<leader>ggo", "<cmd>GForgeOpenedIssues<CR>", desc = "List opened issue" },
        { "<leader>ggp", "<cmd>GForgePinnedIssues<CR>", desc = "List pinned issues" },
        {
            "<leader>gio", function() require(ia).list_issues({ state = "open", limit = 100, }) end,
            desc = "List All Open Issues"
        },
        {
            "<leader>giB", function() require(ia).list_issues({ state = "open", labels = "bug", limit = 100, }) end,
            desc = "List All Open Bugs"
        },
        {
            "<leader>gim", function() require(ia).list_issues({ state = "open", assignee = "@me", }) end,
            desc = "List My Issues"
        },
        {
            "<leader>gib", function() require(ia).list_issues({ state = "open", assignee = "@me", labels = "bug", }) end,
            desc = "List My Bugs"
        },
    },
    opts = {},
}
```

</details>

Please call any of the following commands  to see if any issues are detected by the plugin:
- `:checkhealth gitforge` to check the overall plugin health
- `:checkhealth gitforge.gh` to check the Github provier
- `:checkhealth gitforge.glab` to check the GitLab provier

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

### Issue Buffers

Interacting with an issue buffer is done through key binding using the `<localleader>` key.
Closing an issue is done with `q`. The key bindings are configurable as [documented here](/docs/configuration.md#issue-settings).

| Single Issue             | Default Binding         | Github | Gitlab |
| -----------------------: | :---------------------: | :----: | :----: |
| View an Issue            | `:GForgeViewIssue`      |   ✓    |   ✓    |
| Create New Issue         | `:GForgeCreateIssue`    |   ✓    |   ✓    |
| List All Issues          | `:GForgeListIssues`     |   ✓    |   ✓    |
| List Locally Open Issues | `:GForgeOpenedIssues`   |   ✓    |   ✓    |
| List Pinned Issues       | `:GForgePinnedIssues`   |   ✓    |   ✓    |


| Issue-Buffer Actions     | Default Binding         | Github | Gitlab |
| -----------------------: | :---------------------: | :----: | :----: |
| Hide Issue               | `q`                     |   ✓    |   ✓    |
| Refresh Content          | `<localleader>u`        |   ✓    |   ✓    |
| Edit Title               | `<localleader>t`        |   ✓    |   ✓    |
| Edit Labels              | `<localleader>l`        |   ✓    |   ✓    |
| Edit Assignees           | `<localleader>a`        |   ✓    |   ✓    |
| Edit Description         | `<localleader>d`        |   ✓    |   ✓    |
| Open/Close Issue         | `<localleader>s`        |   ✓    |   ✓    |
| Add comment              | `<localleader>c`        |   ✓    |   ✓    |
| Pin Issue                | `<localleader>p`        |   ✓    |   ✓    |
| Open in Browser          | `<localleader>w`        |   ✓    |   ✓    |

### Label Picker

| Action                   | Binding            |
| -----------------------: | :----------------: |
| Toggle Label             | `<tab>`            |
| Select Label + Confirm   | `<cr>`             |
| Confirm Selection        | `<esc>`            |
| Quit without changes     | `<C-c>`            |
| Move to next label       | `<C-n>` / `<Down>` |
| Move to previous label   | `<C-p>` / `<Up>`   |
| Move page up             | `<C-u>`            |
| Move page down           | `<C-d>`            |

The values presented in the picker are:
1. the cached project labels
1. the retrieved list of project labels.

Labels are always retrieved and on success stored in the cache. If the labels changed
upstream, this is not automatically propagated into the picker. In this case, only the
next label-picker usage will show the new labels. This limitation is considered acceptable,
given the relative static nature of labels.

### Configuration

This plugin probably requires a bit of configuration to select the elements issues that are of your interest.
Smaller projects are probably fine without the more complicated key bindings. Large projects certainly aren't.
Viewing only issues with specific labels, e.g. for a subproject is possible, but requires calling the matching
`lua` functions with proper arguments.

See [docs/configuration.md](docs/configuration.md) for more information on how to configure the plugin.

## Plugins that will improve the user experience

- [markview.nvim](https://github.com/OXY2DEV/markview.nvim) or [render-markdown.nvim](https://github.com/MeanderingProgrammer/render-markdown.nvim) for markdown visualization
- [neogit](https://github.com/NeogitOrg/neogit) for direct `git` interaction
- for better `vim.ui.input` and notifications, there are multiple options
    - [snacks.nvim](https://github.com/folke/snacks.nvim)
    - [dressing.nvim](https://github.com/stevearc/dressing.nvim)
    - [nvim-notify](https://github.com/rcarriga/nvim-notify)
- [toggleterm.nvim](https://github.com/akinsho/toggleterm.nvim) to quickly execute cli commands directly

## Plugins you might want to use instead

- [jirac.nvim](https://github.com/janBorowy/jirac.nvim)
- [gitlab.nvim](https://github.com/harrisoncramer/gitlab.nvim)

## Status

### Issues

The issue interactions are ready to work with. Please create issues if you experience problems.
Right now, only single-issue interactions are available. Switch to the Web-View directly from
`nvim` if necessary.

### Pull Requests

No work has been done.

### CI/Commands

No work has been done.
