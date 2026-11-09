# Planning Center Services API

Use `pro-crud planning-center` to authenticate with Planning Center Services,
find remote IDs, and transfer individual `.pro` attachments. These commands
contact Planning Center directly; they do not require the Planning Center MCP
or a running ProPresenter instance. Local playlist edit commands remain local.

## Sign in

```sh
pro-crud planning-center login
pro-crud planning-center status
pro-crud planning-center logout
```

OAuth opens the browser on this Mac and waits up to three minutes at
`http://127.0.0.1:49173/oauth/callback`. The registered public OAuth application
must permit that exact callback URL and support PKCE. The CLI requests only the
`services` scope and uses no client secret. `login --no-browser` prints the URL
for opening manually on the same Mac. Tokens are saved in macOS Keychain and
refreshed when needed. `logout` removes local credentials; revoke authorization
in Planning Center if remote revocation is also needed.

For a church's own local automation, personal access tokens work in every build,
including builds without an OAuth client ID:

```sh
pro-crud planning-center login --personal-access-token
```

Enter the PAT's application ID and secret when prompted. The secret prompt does
not echo. For noninteractive login, supply `PLANNING_CENTER_PAT_ID` and
`PLANNING_CENTER_PAT_SECRET` through the process environment. Do not place them
in command arguments, source files, or logs. The CLI checks Services access
before replacing credentials in Keychain. API permissions follow the user who
created or authorized the credentials. Planning Center requires OAuth for
integrations serving multiple churches.

## Find the destination

Discovery and attachment commands return JSON. List commands follow pagination.
Use returned IDs rather than relying on a title to uniquely identify a song.

```sh
pro-crud planning-center list service-types
pro-crud planning-center list plans --service-type 123
pro-crud planning-center list items --service-type 123 --plan 456
pro-crud planning-center list songs --title 'Amazing Grace'
pro-crud planning-center list arrangements --song 789
pro-crud planning-center list keys --song 789 --arrangement 234
pro-crud planning-center list media
pro-crud planning-center attachments list --song 789 --arrangement 234
```

Plan items include remote song/arrangement/key/media relationships. Resolve the
arrangement actually scheduled in the plan. Arrangement attachments are available
in every key; a key-specific attachment is visible only for the selected key.
A general plan attachment does not establish a song-arrangement association.

## Upload a presentation

```sh
pro-crud planning-center attachments upload 'Amazing Grace.pro' \
  --song 789 --arrangement 234 --dry-run
pro-crud planning-center attachments upload 'Amazing Grace.pro' \
  --song 789 --arrangement 234
```

Upload validates the individual `.pro` locally, uploads its bytes, creates an
attachment on the explicit song arrangement, and reads it back for verification.
The result contains the attachment ID. `--dry-run` validates and reports the
local file and remote destination without making network requests.

Uploads create new attachments and preserve existing ones. Inspect the destination
before retrying an interrupted upload; attachment creation is not automatically
retried and a server may have accepted a request whose response was lost. Keep
one intended `.pro` per arrangement when possible to avoid ambiguous automatic
selection. This command currently uploads to song arrangements only.

In ProPresenter, enable **Automatically Download Presentations and Media**, set
**Download Library**, and import the plan using **+ → Planning Center Service**.
Verify the presentation linked to the song. Existing library matching can link
another local copy. Apply **Update Available** when offered, or use the item's
Planning Center Attachment Manager to select the intended attachment manually.
The CLI upload does not import a plan, replace an existing local link, or trigger
slides. Presentation backgrounds and other referenced slide media are not
synchronized by ProPresenter's Planning Center integration.

## Download an attachment

```sh
pro-crud planning-center attachments download 567 \
  --song 789 --arrangement 234 --output 'Downloaded Song.pro'
```

List and download support these mutually exclusive destination forms:

- `--song ID --arrangement ID`, optionally with `--key ID`.
- `--media ID`.
- `--service-type ID --plan ID`, optionally with `--item ID`.

Plan and item attachment lists contain only files attached directly at that
location. They do not aggregate files inherited from a linked song, arrangement,
key, or media item; list those destinations separately using their IDs.

Download obtains the file URL through the API's attachment `open` action and
saves the file without sending API credentials to the file host. The explicit
output path must not exist. Download does not import or link the file in
ProPresenter; validate and inspect a downloaded `.pro` before using it.

HTTP failures produce a nonzero exit status. Rate-limit errors report the
server's retry interval. A newly uploaded file can briefly return Planning
Center's specific S3-not-ready response. Download retries that rejected `open`
action after 1, 2, and 4 seconds, then reports failure if it is still unavailable.
Other errors and file/attachment creation requests are not retried. Credential
values and raw authentication response bodies are not printed.

## Official API documentation

- [Authentication](https://api.planningcenteronline.com/docs/overview/authentication)
- [File uploads](https://api.planningcenteronline.com/docs/overview/file-uploads)
- [Services attachments](https://api.planningcenteronline.com/docs/apps/services/versions/2018-11-01/vertices/attachment)
