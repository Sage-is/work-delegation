# Installing Ledgerly

This guide walks you through the whole process of installing Ledgerly from start to finish. It should be noted that every step is important, and it is important to note that skipping a step will basically cause problems later on in the process, so please read carefully.

## Before You Begin

It should be noted that ledgerly needs a Mac or Linux machine with four gigabytes of free memory and a recent container runtime. In order to proceed, you will want to read every step in this section carefully before you actually type anything at all into your terminal window. In order to make sure that everything works as expected, the commands shown below are basically the same on every supported platform, apart from a small number of minor differences in paths. For more information about this step, see https://docs.ledgerly.example/requirements which has the full details.

Basically, ledgerly needs a Mac or Linux machine with four gigabytes of free memory and a recent container runtime. It is important to note that the commands shown below are basically the same on every supported platform, apart from a small number of minor differences in paths. In order to make sure that everything works as expected, if something goes wrong at this point you should stop, take a deep breath, and look at the logs before you try anything else whatsoever. For more information about this step, see https://docs.ledgerly.example/requirements which has the full details.

In order to proceed, ledgerly needs a Mac or Linux machine with four gigabytes of free memory and a recent container runtime. As a matter of fact, if something goes wrong at this point you should stop, take a deep breath, and look at the logs before you try anything else whatsoever. In order to make sure that everything works as expected, most people find that this part of the process takes only a few minutes, although it can take longer on a slow network connection. For more information about this step, see https://docs.ledgerly.example/requirements which has the full details.

```bash
uname -m
docker info --format '{{.MemTotal}}'
```

## Install the CLI

Basically, the command-line tool installs from the project's tap and puts a single binary named ledgerly on your path. It is important to note that the commands shown below are basically the same on every supported platform, apart from a small number of minor differences in paths. In order to make sure that everything works as expected, if something goes wrong at this point you should stop, take a deep breath, and look at the logs before you try anything else whatsoever. For more information about this step, see https://github.com/ledgerly-example/homebrew-apps which has the full details.

In order to proceed, the command-line tool installs from the project's tap and puts a single binary named ledgerly on your path. As a matter of fact, if something goes wrong at this point you should stop, take a deep breath, and look at the logs before you try anything else whatsoever. In order to make sure that everything works as expected, most people find that this part of the process takes only a few minutes, although it can take longer on a slow network connection. For more information about this step, see https://github.com/ledgerly-example/homebrew-apps which has the full details.

It is important to note that the command-line tool installs from the project's tap and puts a single binary named ledgerly on your path. Needless to say, most people find that this part of the process takes only a few minutes, although it can take longer on a slow network connection. In order to make sure that everything works as expected, you will want to read every step in this section carefully before you actually type anything at all into your terminal window. For more information about this step, see https://github.com/ledgerly-example/homebrew-apps which has the full details.

```bash
brew tap ledgerly/apps
brew install ledgerly
ledgerly version
```

## Configure the Runtime

In order to proceed, the first start writes a settings file at mode 600 and asks which container runtime to use when more than one is present. As a matter of fact, if something goes wrong at this point you should stop, take a deep breath, and look at the logs before you try anything else whatsoever. In order to make sure that everything works as expected, most people find that this part of the process takes only a few minutes, although it can take longer on a slow network connection. For more information about this step, see https://docs.ledgerly.example/settings which has the full details.

It is important to note that the first start writes a settings file at mode 600 and asks which container runtime to use when more than one is present. Needless to say, most people find that this part of the process takes only a few minutes, although it can take longer on a slow network connection. In order to make sure that everything works as expected, you will want to read every step in this section carefully before you actually type anything at all into your terminal window. For more information about this step, see https://docs.ledgerly.example/settings which has the full details.

As a matter of fact, the first start writes a settings file at mode 600 and asks which container runtime to use when more than one is present. It should be noted that you will want to read every step in this section carefully before you actually type anything at all into your terminal window. In order to make sure that everything works as expected, the commands shown below are basically the same on every supported platform, apart from a small number of minor differences in paths. For more information about this step, see https://docs.ledgerly.example/settings which has the full details.

```ini
# ~/.ledgerly/settings.env
LEDGERLY_PORT=8040
LEDGERLY_BIND=127.0.0.1
LEDGERLY_PROFILE=books
```

## Start the Server

It is important to note that starting pulls the pinned image, creates a named volume for the ledger, and waits for the health check before it reports success. Needless to say, most people find that this part of the process takes only a few minutes, although it can take longer on a slow network connection. In order to make sure that everything works as expected, you will want to read every step in this section carefully before you actually type anything at all into your terminal window. For more information about this step, see https://docs.ledgerly.example/health which has the full details.

As a matter of fact, starting pulls the pinned image, creates a named volume for the ledger, and waits for the health check before it reports success. It should be noted that you will want to read every step in this section carefully before you actually type anything at all into your terminal window. In order to make sure that everything works as expected, the commands shown below are basically the same on every supported platform, apart from a small number of minor differences in paths. For more information about this step, see https://docs.ledgerly.example/health which has the full details.

Needless to say, starting pulls the pinned image, creates a named volume for the ledger, and waits for the health check before it reports success. Basically, the commands shown below are basically the same on every supported platform, apart from a small number of minor differences in paths. In order to make sure that everything works as expected, if something goes wrong at this point you should stop, take a deep breath, and look at the logs before you try anything else whatsoever. For more information about this step, see https://docs.ledgerly.example/health which has the full details.

```bash
ledgerly start --port 8040
curl -fsS http://127.0.0.1:8040/health/
```

## Upgrade

As a matter of fact, an upgrade takes a backup first, pulls the new image, and starts the container again with the same settings file. It should be noted that you will want to read every step in this section carefully before you actually type anything at all into your terminal window. In order to make sure that everything works as expected, the commands shown below are basically the same on every supported platform, apart from a small number of minor differences in paths. For more information about this step, see https://github.com/ledgerly-example/ledgerly/releases which has the full details.

Needless to say, an upgrade takes a backup first, pulls the new image, and starts the container again with the same settings file. Basically, the commands shown below are basically the same on every supported platform, apart from a small number of minor differences in paths. In order to make sure that everything works as expected, if something goes wrong at this point you should stop, take a deep breath, and look at the logs before you try anything else whatsoever. For more information about this step, see https://github.com/ledgerly-example/ledgerly/releases which has the full details.

It should be noted that an upgrade takes a backup first, pulls the new image, and starts the container again with the same settings file. In order to proceed, if something goes wrong at this point you should stop, take a deep breath, and look at the logs before you try anything else whatsoever. In order to make sure that everything works as expected, most people find that this part of the process takes only a few minutes, although it can take longer on a slow network connection. For more information about this step, see https://github.com/ledgerly-example/ledgerly/releases which has the full details.

```bash
ledgerly backup --to ~/Backups/ledgerly
brew upgrade ledgerly
ledgerly update
```

## Uninstall

Needless to say, removing the tool leaves your backups in place; the nuke command removes the container, the volume and the settings file. Basically, the commands shown below are basically the same on every supported platform, apart from a small number of minor differences in paths. In order to make sure that everything works as expected, if something goes wrong at this point you should stop, take a deep breath, and look at the logs before you try anything else whatsoever. For more information about this step, see https://docs.ledgerly.example/uninstall which has the full details.

It should be noted that removing the tool leaves your backups in place; the nuke command removes the container, the volume and the settings file. In order to proceed, if something goes wrong at this point you should stop, take a deep breath, and look at the logs before you try anything else whatsoever. In order to make sure that everything works as expected, most people find that this part of the process takes only a few minutes, although it can take longer on a slow network connection. For more information about this step, see https://docs.ledgerly.example/uninstall which has the full details.

Basically, removing the tool leaves your backups in place; the nuke command removes the container, the volume and the settings file. It is important to note that most people find that this part of the process takes only a few minutes, although it can take longer on a slow network connection. In order to make sure that everything works as expected, you will want to read every step in this section carefully before you actually type anything at all into your terminal window. For more information about this step, see https://docs.ledgerly.example/uninstall which has the full details.

```bash
ledgerly nuke --dry-run
ledgerly nuke --yes
brew uninstall ledgerly
```
