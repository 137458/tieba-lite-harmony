const LOGIN_URL_PATTERN: RegExp = /^https:\/\/(?:wappass\.baidu\.com\/passport(?:[\/?#]|$)|passport\.baidu\.com\/(?:[\/?#]|$)|tieba\.baidu\.com\/(?:[\/?#]|$)|tiebac\.baidu\.com\/(?:[\/?#]|$))/;
const LOGIN_SUCCESS_URL_PATTERN: RegExp = /^https:\/\/(?:tieba\.baidu\.com|tiebac\.baidu\.com)\/index\/tbwise\/(?:[\/?#]|$)/;

export function isAllowedLoginUrl(url: string): boolean {
  if (url.length === 0) {
    return false;
  }
  return LOGIN_URL_PATTERN.test(url);
}

export function isLoginSuccessUrl(url: string): boolean {
  if (!isAllowedLoginUrl(url)) {
    return false;
  }
  return LOGIN_SUCCESS_URL_PATTERN.test(url);
}
