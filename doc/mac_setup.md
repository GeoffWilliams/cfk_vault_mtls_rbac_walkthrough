# macOS setup instruictions

1. [git](https://git-scm.com/), [OpenSSL](https://www.openssl.org/)
    * should already be installed
2. Docker - must use Docker since `podman` doesnt work properly on macOS with K3D
    * Corporates: follow installation instructions from IT to allocate appropriate Docker Desktop license.
    * Install via SSH: (eg for writing instructions for macOS), following https://docs.docker.com/desktop/install/mac-install/#install-from-the-command-line Instructions for starting Docker from the command line https://github.com/docker/for-mac/issues/6504 dont work (any more?). Install using SSH, then login with VNC to start the daemon.
        a. Install `rosetta: softwareupdate --install-rosetta`
        b. `curl -O "https://desktop.docker.com/mac/main/arm64/Docker.dmg?utm_source=docker&utm_medium=webreferral&utm_campaign=docs-driven-download-mac-arm64"`
        c. `sudo hdiutil attach Docker.dmg`
        d. `sudo /Volumes/Docker/Docker.app/Contents/MacOS/install --accept-license`
        e. `/Volumes/Docker/Docker.app/Contents/Resources/bin/docker run hello-world`
        f. Login with VNC, start Docker Daemon
    * Docker Desktop GUI settings:
        * Increase CPU (8)
        * Increase Memory (16GB)
        * Increase Swap (4GB)
        * Increase Virtual disk limit (100GB)
        * `Apply and Restart`
    * Prove docker works: `docker run hello-world`
3. [K3D](https://k3d.io/v5.4.1/#installation)
4. JDK: `brew install java` and follow the instructions to update your shell
5. `yq`: `brew install yq`
6. `jq`: `brew install jq`
7. Confluent CLI: `brew install confluentinc/tap/cli`
8. CFSSL: `go install github.com/cloudflare/cfssl/cmd/...@latest`
9. [helm](https://helm.sh/): `brew install helm`

