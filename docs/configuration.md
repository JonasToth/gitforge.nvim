# Configuration

This page shows the available configuration options and their corresponding default values.
The out-of-the-box experience will use Github.

## General Settings

General settings that change the default experience:

```lua
M.opts.timeout = 3500
-- one of:
-- gitforge.gh.issue
-- gitforge.glab.issue
M.opts.default_issue_provider = "gitforge.gh.issue"
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
