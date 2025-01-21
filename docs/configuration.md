# Configuration

This page shows the available configuration options and their corresponding default values.
The out-of-the-box experience will use Github.

## General Settings

General settings that change the default experience:

```lua
-- Timeout of provider-commands.
M.opts.timeout = 3500
-- one of:
-- gh
-- glab
M.opts.default_issue_provider = "gh"
-- Number of character after cut-off in telescope list view.
M.opts.list_max_title_length = 60
```

## Project Settings

It is possible to selectively configure specific directories to change their project setings.
When creating the issue provider, all elements are searched in order. For the first entry that
matches its `path` with `nvim`s current working directory is selected for configuration. Paths
are expanded and normalized before matching. Matching is done on a prefix-searching.

```lua
-- Only 'path' is mandatory. At least one more other element should be provided to have an effect.
opts.projects = {
    -- Configure this project to use GitLab instead of Github.
    { path = "~/software/my-project",   issue_provider = "glab" },
    -- A clone of 'https://github.com/gl-cli/glab', that uses issues from 'https://gitlab.com/gitlab-org/cli'.
    { path = "~/software/glab",         issue_provider = "glab", project = "gitlab.com/gitlab-org/cli" },
    -- My own fork of LLVM, but issues are taken from the upstream repository.
    { path = "~/software/llvm-project", issue_provider = "gh",   project = "github.com/llvm/llvm-project" },
}
```

## Issue Settings

Keys to interact on an issue buffer:

```lua
opts.issue_keys = {
    close = "q"
    update = "<localleader>u"
    comment = "<localleader>c"
    title = "<localleader>t"
    labels = "<localleader>l"
    assignees = "<localleader>a"
    description = "<localleader>d"
    state = "<localleader>s"
    pin = "<localleader>p"
    webview = "<localleader>w"
}
```


## Github Settings

Github specific settings:

```lua
opts.github.executable = "gh"
```

## GitLab Settings

GitLab specific settings:

```lua
opts.gitlab.executable = "glab"
```
