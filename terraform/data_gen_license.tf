#
# ShadowTraffic license download (OS-agnostic)
#

data "http" "shadowtraffic_license" {
  url = "https://raw.githubusercontent.com/ShadowTraffic/shadowtraffic-examples/master/free-trial-license-docker.env"
}

resource "local_file" "shadowtraffic_license" {
  filename = "${path.module}/data-gen/free-trial-license-docker.env"
  content  = data.http.shadowtraffic_license.response_body
}


