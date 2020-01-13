function pgit () {
    (docker run -ti --rm -v ${HOME}/personal/gitconfig:/root -v $(pwd):/git alpine/git "$@")
}

