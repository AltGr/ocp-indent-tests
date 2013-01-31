This repo is intended to facilitate testing of ocp-indent against larger bases
of code, which we don't want included inside its repo.

Sources to run on are defined in file `sources`, in the format `name url ocp-indent-params`, eg `mypackage http://mysite.com/mypackage.tar.gz -c match_clause=2,with=2`

Current result of indentation is stored in directory `current`.

* `make test` should download the sources and tell you how your version compares
  to the original source and the current status.
* `make xxx.test` tests only for sources matching `xxx`
* `make xxx.meld` will give you a three-way diff for source `xxx`
* `make xxx.meld-changes` will tell you what is changed between your ocp-indent
  and what is versionned here. Useful to see the consequences of changes in
  ocp-indent.
* `make current` will store your state as current

Obviously, you need meld. You may also diff manually between orig/xxx and new/xxx to see how our indent differs from the original.
