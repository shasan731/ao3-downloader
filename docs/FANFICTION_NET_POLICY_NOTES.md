# FanFiction.net policy and compatibility notes

ArchiveBind accepts only an explicit public `https://www.fanfiction.net/s/…` story URL supplied by the user. It does not browse categories, search profiles, collect account data, import cookies, sign in, use mirrors, or bypass verification/security features.

FanFiction.net’s current [Terms of Service](https://www.fanfiction.net/tos/) allow access for personal use and prohibit automated systems that send more requests than a person could reasonably produce with a conventional browser. ArchiveBind therefore uses the same global serialized queue as AO3, defaults to at least 15 seconds between request lifecycles, honors `Retry-After`, fetches only the chapters needed for the requested story, and never downloads chapters concurrently. Its [robots.txt](https://www.fanfiction.net/robots.txt) currently publishes a five-second crawl delay; ArchiveBind’s default is deliberately slower. These engineering choices are not a legal determination or a guarantee of site approval. Users remain responsible for current terms, applicable law, personal-use limits, and creators’ choices.

FanFiction.net may place Cloudflare browser verification in front of story pages. Compatibility can vary by network, location, and time. ArchiveBind detects this page, reports a challenge, and stops. It will not imitate a browser, solve a challenge, or reuse a browser session.

The site has no native ordered-series model equivalent to AO3 series. ArchiveBind supports complete individual stories—including all published chapters—but does not reinterpret communities, favorites, or profile lists as series.

Automated tests use small synthetic HTML fixtures and never contact FanFiction.net. A supervised, low-volume real-site check is required when the site permits ordinary client access.
