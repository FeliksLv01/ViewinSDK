package app.viewin.protocol

import kotlinx.serialization.json.Json

/** Unknown optional fields are permitted by the 0.1 wire contract. */
val ViewinJson = Json {
    ignoreUnknownKeys = true
    encodeDefaults = true
}
