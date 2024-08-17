# Goal and Non-Goals

In short, this plugin tries to provide access to
- issues
- pull requests
- CI/CD
for a variety of git forges, namely GitHub, GitLab, Jira (issues at least)/Bitbucket and maybe
Gitea.

The goal of this plugin is to keep most daily developer interactions with the projects git forge
within `nvim`. Especially quick actions like assigning an issue or writing a comment should not
require a context switch to browser. It goes for functionality first, then customizability and
finally asthetics.

Providing advanced features like project management or "normal browsing" you can do on e.g. on
GitHub are _not_ in scope of this plugin.

## Motivation

I never developed a plugin for `nvim` and have no prior experience in `Lua`. That will be reflected
in the code you may read :)
The plugin shall serve a personal wish for tighter integration of issue work into my personal `nvim`.
It is open for everyone to suggest improvements or maybe even implement them. Given the hobby nature
of the work, I will try to keep it focussed.
The development documents will hopefully help in communicating my personal priorities.

Advice, help and suggestions are always welcome!

## Definition of Done

Version 1.0 is when I can perform day to day work with issues, pull requests and CI/CD interaction
with GitHub, Bitbucket and Jira. Other git forges (especially if providing a CLI tool) may be
integrated but are second class citizens. Why? Because I don't use them.
If anyone has stakes into something else, go ahead and support me :)
