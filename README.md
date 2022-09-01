# start-kadena

This is the Nix magic that I use locally on my macOS machine to run a Kadena
node plus chainweb-data for collecting network information. Basic use:

1. Start a local postgresql server, and follow the instructions after
   chainweb-data fails the first time.

2. Make sure that port 1790 on your public facing firewall redirect TCP/UDP
   traffic to the host you will run this node on.

3. Create the directories `~/.local/share/chainweb-node` and
   `~/.local/share/chainweb-data`. These could also be symlinks to directories
   on an external SSD, for example.

4. `nix build -f . start-kadena`

5. `./result/bin/start-kadena`

This will start a `tmux` session with two panes: One running chainweb-node,
and the other running chainweb-data to collect data from that node. Note that
you will need at least 100 GB for the node, and 90 GB for data, and these
values will increase over time, so my suggestion is 500 GB minimum over the
next year.

The chainweb-node log will be very spare, containing only information messages
about cut progression, and error or fatal messsages. This log will be
collected in `~/.local/share/chainweb-node`.

If you'd like to monitor the block progression of your node, you can use a
utility like `watch` or `GeekTool` to monitor the output of this command:

```
/usr/bin/curl --connect-timeout 1 -k -s \
    "http://127.0.0.1:1848/chainweb/0.0/mainnet01/cut" \
    | jq -r '.height / 20 | floor | tostring | [while(length>0; .[:-3]) | .[-3:]] | reverse | join(",")'
```
