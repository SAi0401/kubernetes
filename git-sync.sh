FROM alpine:latest
RUN apk update && apk upgrade && \
    apk add --no-cache bash git openssh
ENV WORKDIR dummy
ENV REMOTE dummy
WORKDIR /scripts
COPY  ./git-sync.sh /scripts
RUN chmod a+x /scripts/*.sh
RUN mkdir /root/.ssh/
ADD ./id_rsa /root/.ssh/id_rsa
RUN ssh-keyscan bitbucket.org >> /root/.ssh/known_hosts
CMD /scripts/git-sync.sh $WORKDIR $REMOTE


---



#!/bin/bash

WORKDIR=$1
REMOTE=$2
# Default to git pull with FF merge for current branch
GIT_COMMAND="git pull"


if [ $# -eq 1 ]; then
  WORKDIR="$1"
fi

if [ -d "$WORKDIR/.git" ]; then
  cd "$WORKDIR"
  # update remote tracking branch
  git remote update
  if (( $? )); then
      echo "$(date) Unable to fetch the remote repository!"
      exit 1
  else
      LOCAL_SHA=$(git rev-parse --verify HEAD)
      REMOTE_SHA=$(git rev-parse --verify FETCH_HEAD)
      if [ $LOCAL_SHA = $REMOTE_SHA ]; then
          echo "$(date) The local repository is up to date with remote. No sync is needed."
          exit 0
      else
          $GIT_COMMAND
          if (( $? )); then
              echo "$(date) Unable to update the local repository!"
              exit 1
          else
              echo "$(date) Update complete."
              exit 0
          fi
      fi
  fi
else
  echo "$(date) This directory has not been initialized with git, creating new dir and cloning repository"
  rm -rf $WORKDIR
  mkdir -p $WORKDIR
  git clone $REMOTE $WORKDIR
  if (( $? )); then
    echo "$(date) Failed to clone remote repository!"
    exit 1
  else 
    echo "$(date) Repository cloned successfully"
    exit 0
  fi
  
fi
