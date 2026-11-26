#!/usr/bin/env python3
"""SMB2 share for the AetherTV smoke test, backed by impacket.

Usage: smb_server.py HOST PORT SHARE_NAME SHARE_PATH USER PASSWORD

Needs impacket (pip install impacket). With an empty USER the share accepts
anonymous sessions. Listen on a high port so no privileges are needed. Logs
to stderr.
"""
import logging
import sys

from impacket import smbserver
from impacket.ntlm import compute_lmhash, compute_nthash


def main(argv):
    if len(argv) != 7:
        sys.exit(__doc__)
    host, port, share, path = argv[1], int(argv[2]), argv[3], argv[4]
    user, password = argv[5], argv[6]
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

    server = smbserver.SimpleSMBServer(listenAddress=host, listenPort=port, ipv6=False)
    server.addShare(share.upper(), path, "AetherTV smoke test", readOnly="yes")
    server.setSMB2Support(True)
    server.setSMBChallenge("")
    if user:
        server.addCredential(user, 0, compute_lmhash(password), compute_nthash(password))

    sys.stderr.write(f"smb: share \\\\{host}\\{share.upper()} -> {path} on port {port} "
                     f"(auth {'on' if user else 'anonymous'})\n")
    sys.stderr.flush()
    server.start()


if __name__ == "__main__":
    main(sys.argv)
