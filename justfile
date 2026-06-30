test:
  mix test

format:
  mix format --migrate

readmix:
  mix rdmx.update README.md

_libdev_check:
  mix libdev.check

_git_status:
  git status

check: format readmix _libdev_check _git_status
