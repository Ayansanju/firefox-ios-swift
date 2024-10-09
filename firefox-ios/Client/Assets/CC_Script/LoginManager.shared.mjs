/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

/**
 * Code that we can share across Firefox Desktop, Firefox Android and Firefox iOS.
 */

class Logic {
  static inputTypeIsCompatibleWithUsername(input) {
    const fieldType = input.getAttribute("type")?.toLowerCase() || input.type;
    return (
      ["text", "email", "url", "tel", "number", "search"].includes(fieldType) ||
      fieldType?.includes("user")
    );
  }

  /**
   * Test whether the element has the keyword in its attributes.
   * The tested attributes include id, name, className, and placeholder.
   */
  static elementAttrsMatchRegex(element, regex) {
    if (
      regex.test(element.id) ||
      regex.test(element.name) ||
      regex.test(element.className)
    ) {
      return true;
    }

    const placeholder = element.getAttribute("placeholder");
    return placeholder && regex.test(placeholder);
  }

  /**
   * Test whether associated labels of the element have the keyword.
   * This is a simplified rule of hasLabelMatchingRegex in NewPasswordModel.sys.mjs
   */
  static hasLabelMatchingRegex(element, regex) {
    return regex.test(element.labels?.[0]?.textContent);
  }

  /**
   * Get the parts of the URL we want for identification.
   * Strip out things like the userPass portion and handle javascript:.
   */
  static getLoginOrigin(uriString, allowJS = false) {
    try {
      const mozProxyRegex = /^moz-proxy:\/\//i;
      if (mozProxyRegex.test(uriString)) {
        // Special handling for moz-proxy URIs
        const uri = new URL(uriString.replace(mozProxyRegex, "https://"));
        return `moz-proxy://${uri.host}`;
      }

      const uri = new URL(uriString);
      if (uri.protocol === "javascript:") {
        return allowJS ? "javascript:" : null;
      }

      // Ensure the URL has a host
      // Execption: file URIs See Bug 1651186
      return uri.host || uri.protocol === "file:"
        ? `${uri.protocol}//${uri.host}`
        : null;
    } catch {
      return null;
    }
  }

  static getFormActionOrigin(form) {
    let uriString = form.action;

    // A blank or missing action submits to where it came from.
    if (uriString == "") {
      // ala bug 297761
      uriString = form.baseURI;
    }

    return this.getLoginOrigin(uriString, true);
  }

  /**
   * Checks if a field type is username compatible.
   *
   * @param {Element} element
   *                  the field we want to check.
   * @param {Object} options
   * @param {bool} [options.ignoreConnect] - Whether to ignore checking isConnected
   *                                         of the element.
   *
   * @returns {Boolean} true if the field type is one
   *                    of the username types.
   */
  static isUsernameFieldType(element, { ignoreConnect = false } = {}) {
    if (!HTMLInputElement.isInstance(element)) {
      return false;
    }

    if (!element.isConnected && !ignoreConnect) {
      // If the element isn't connected then it isn't visible to the user so
      // shouldn't be considered. It must have been connected in the past.
      return false;
    }

    if (element.hasBeenTypePassword) {
      return false;
    }

    if (!Logic.inputTypeIsCompatibleWithUsername(element)) {
      return false;
    }

    let acFieldName = element.getAutocompleteInfo().fieldName;
    if (
      !(
        acFieldName == "username" ||
        acFieldName == "webauthn" ||
        // Bug 1540154: Some sites use tel/email on their username fields.
        acFieldName == "email" ||
        acFieldName == "tel" ||
        acFieldName == "tel-national" ||
        acFieldName == "off" ||
        acFieldName == "on" ||
        acFieldName == ""
      )
    ) {
      return false;
    }
    return true;
  }

  /**
   * Checks if a field type is password compatible.
   *
   * @param {Element} element
   *                  the field we want to check.
   * @param {Object} options
   * @param {bool} [options.ignoreConnect] - Whether to ignore checking isConnected
   *                                         of the element.
   *
   * @returns {Boolean} true if the field can
   *                    be treated as a password input
   */
  static isPasswordFieldType(element, { ignoreConnect = false } = {}) {
    if (!HTMLInputElement.isInstance(element)) {
      return false;
    }

    if (!element.isConnected && !ignoreConnect) {
      // If the element isn't connected then it isn't visible to the user so
      // shouldn't be considered. It must have been connected in the past.
      return false;
    }

    if (!element.hasBeenTypePassword) {
      return false;
    }

    // Ensure the element is of a type that could have autocomplete.
    // These include the types with user-editable values. If not, even if it used to be
    // a type=password, we can't treat it as a password input now
    let acInfo = element.getAutocompleteInfo();
    if (!acInfo) {
      return false;
    }

    return true;
  }
}

export { Logic };