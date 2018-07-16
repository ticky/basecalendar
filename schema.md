# Schema Sketchbook

## User

`uuid`: UUID PRIMARY KEY NOT NULL (not exposed, used only by app)
`37signals_user_id`: text NOT NULL (e.g. `14340890`)
`access_token`: random base32 NOT NULL (used to access user's calendars)

## Basecamp Token

`uuid`: UUID PRIMARY KEY NOT NULL
`user_uuid`: UUID NOT NULL (foreign key on `User`)
`token`: string NOT NULL
`refresh_token`: string NOT NULL
`expires_at`: DATE NOT NULL
