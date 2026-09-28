resource "google_firestore_database" "roastfolio" {
  name        = var.app
  location_id = var.region
  type        = "FIRESTORE_NATIVE"

  depends_on = [google_project_service.apis]
}

# TTL deletes lazily (usually within 24 h of expiry); the API also checks expiresAt itself.
# No index_config: the field keeps the inherited single-field indexes.
resource "google_firestore_field" "roasts_ttl" {
  database   = google_firestore_database.roastfolio.name
  collection = "roasts"
  field      = "expiresAt"

  ttl_config {}
}
