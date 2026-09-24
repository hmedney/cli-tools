FROM python:3.12-slim-trixie

ARG NODEJS_VERSION="24"
ARG NVM_VERSION="v0.40.6"

# Capture host credentials
ARG CURRENT_HOME
ARG CURRENT_USERNAME
ARG CURRENT_UID
ARG CURRENT_GID

# Create matching host system user
RUN groupadd --gid $CURRENT_GID $CURRENT_USERNAME \
  && useradd --uid $CURRENT_UID --gid $CURRENT_GID -m -s /bin/bash $CURRENT_USERNAME

# Install packages
RUN apt-get update && apt-get install -y --no-install-recommends \
  bash \
  openssh-server \
  ca-certificates \
  libatomic1 \
  curl \
  file \
  micro \
  git \
  jq \
  less \
  bzip2 \
  procps \
  fd-find \
  ripgrep \
  socat \
  libgomp1 \
  locales \
  && echo "en_US.UTF-8 UTF-8" > /etc/locale.gen \
  && locale-gen \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# 5. Shift context completely to the mirrored user
USER $CURRENT_USERNAME
ENV HOME=$CURRENT_HOME
WORKDIR $HOME

# Create Python venv in userspace
ENV PYTHON_VENV=$HOME/venv
RUN python3 -m venv $PYTHON_VENV
ENV PATH=$PYTHON_VENV/bin:$PATH
RUN $PYTHON_VENV/bin/pip install --no-cache-dir --upgrade pip && \
  $PYTHON_VENV/bin/pip install --no-cache-dir ipykernel jupyter_client
ENV SHELL=bash

# install uv
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH=$HOME/.local/bin:$PATH

# Install NodeJs
ENV NVM_SYMLINK_CURRENT=true
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh | bash \
  && export NVM_DIR="$HOME/.nvm" \
  && . $HOME/.nvm/nvm.sh \
  && nvm install $NODEJS_VERSION \
  && nvm use $NODEJS_VERSION \
  && nvm alias default $NODEJS_VERSION \
  && npm install npm@latest -g \
  && npm config set allow-remote all \
  && npm config set allow-scripts all --location=user
ENV PATH=$HOME/.nvm/current/bin:$HOME/bin:$PATH

# install pnpm
RUN curl -fsSL https://get.pnpm.io/install.sh | sh
ENV PATH=$HOME/.local/share/pnpm/bin:$PATH

# install rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH=$HOME/.cargo/bin:$PATH
RUN rustup toolchain install stable

# default editor
ENV EDITOR=micro

# improve tui experience
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV TERM=xterm-256color
ENV COLORTERM=truecolor

# allow for quick tool upgrades
ARG UPGRADE_CACHE_BUST=1

ARG INSTALL_COMMAND
RUN echo "Installing  ${INSTALL_COMMAND}"
RUN bash <<EOF
${INSTALL_COMMAND}
EOF
