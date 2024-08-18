# gitforge.nvim - NeoVim Plugin to Access Your Issues, PRs and CI/CD

This plugin aims to provide integrated access to various Git Forges for your daily development
tasks - working with issues, working with PRs and checking CI/CD pipelines.

Read more about the goals and development milestones under [development resources](development_resources/README.md).

## Status

This plugin is still in its early stages and under heavy development. Usage is not recommended yet.
If you like to tinker around and/or are willing to participate in development, please go ahead and
reach out :)

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
