# Layout Parser: PDF -> structured text. Lives in the `us` multi-region.
resource "google_document_ai_processor" "layout" {
  location     = var.docai_location
  display_name = "${var.app}-layout"
  type         = "LAYOUT_PARSER_PROCESSOR"

  depends_on = [google_project_service.apis]
}

locals {
  docai_processor_id = element(split("/", google_document_ai_processor.layout.name), 5) # projects/N/locations/us/processors/<id>
}
