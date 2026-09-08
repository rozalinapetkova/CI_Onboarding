# Day 1.3 samples — sync adapters

Samples for extending `roi_<initials>_CustomerEchoService` to call **https://restcountries.com/v3.1/alpha/{code}** and merge the response.

| File | Purpose |
|---|---|
| `request_payload.json` | Valid POST body the client sends |
| `request_payload_invalid.json` | Triggers schema validation failure (missing required field) |
| `restcountries_response_sample.json` | Trimmed view of the upstream response |
| `final_response.json` | Merged response the iFlow returns to the client |
| `curl_happy.sh`, `curl_invalid_country.sh` | Test commands |
| `roiam_mergeCountryInfo.groovy` | Groovy v2 script that merges the upstream payload into the response |
| `https_receiver_config.md` | HTTP receiver adapter settings (timeout, retries, Throw Exception) |
| `auth_options.md` | Auth-method picker for the receiver hop |
