# Spec: Configuration

- default configuration
- project configuration
- per query/element customization (adding labels to a query or so)
- tables are filled first with defaults, then with projects, finally with element customization
- starting from the current execution directory of `nvim`, the matching project is searched
- project matching happens with the longest prefix match
- using `~` to make the structure machine independent shall be supported
- maybe adding and additional `root-path` to allow relative definitions
