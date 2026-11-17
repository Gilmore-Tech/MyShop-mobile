# Driver category enrollment

Regular is preselected and required during signup and new vehicle creation. Additional categories remain optional. The API independently enforces Regular; every category requires review before matching.

Drivers can open **My Vehicles → Request categories**, choose additional categories and send a request to their Regional Manager. Approved/pending categories cannot be requested again; rejected categories may be resubmitted. Existing approvals remain active. Requests are blocked while a vehicle revision or removal is pending, or after retirement.

Authorized admins use **Verifications → Vehicles → Manage categories**. `edit_provider_profile` permits category changes; `finalize_verification` permits category decisions. Approved-vehicle edits retain current operating authority while a Coordinator and RM review the revision. New assignments remain pending until explicitly approved under **Per-vehicle ride categories**. Use **Pending category requests** to find requests on already approved vehicles.

Deploy the backend before the mobile update. The accompanying backend migration adds missing Regular enrollments as pending in supported active regions. It does not grant approval or migrate legacy driver-only vehicle evidence.
