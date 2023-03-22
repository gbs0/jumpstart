import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
     toastr.options = {
      debug: false,
      positionClass: "toastr-top-right",
      onclick: null,
      fadeIn: 300,
      fadeOut: 1000,
      timeOut: 5000,
      extendedTimeOut: 1000,
    };

    let flash_key = this.data.get("key");
    let flash_value = this.data.get("value");
    console.log(flash_key, flash_value);

    if (flash_key && flash_value) {
      switch (flash_key) {
        case "notice":
        case "success":
          toastr.success(flash_value);
          break;
        case "info":
          toastr.info(flash_value);
          break;
        case "warning":
          toastr.warning(flash_value);
          break;
        case "alert":
        case "error":
          toastr.error(flash_value);
          break;
        default:
          toastr.success(flash_value);
      }
    }
    
  }
}
