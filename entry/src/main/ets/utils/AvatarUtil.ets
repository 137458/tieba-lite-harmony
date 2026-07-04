// 头像 URL 拼接工具（issue #47 切片0）
// 对齐 aiotieba client.py:1211-1221 + profile/_classdef.py:96-97
//
// portrait 字段是百度用户头像标识符（如 "tb.1.xxx" 或 "tb.0.xxx"），
// 不含域名。客户端按尺寸拼接到 tb.himg.baidu.com：
//   小头像: /sys/portraitn/item/{portrait}
//   中头像: /sys/portrait/item/{portrait}
//   大头像: /sys/portraith/item/{portrait}
//
// 清洗规则（aiotieba profile/_classdef.py:96-97）：
//   protobuf 解码出的 portrait 若含 "?"，需去掉末尾 13 字符
//   （百度 protobuf 字段末尾偶发附加 13 字符垃圾数据）

/** 头像尺寸 */
export type AvatarSize = 's' | 'm' | 'l';

// 协议用 http：对齐 Android TiebaLite StringUtil.kt:156/166 + aiotieba client.py:1221
// 之前误改成 https 导致头像加载失败（commit eb960f5 瞎猜"CDN 支持 https"，实际 CDN 证书不匹配 https）
const AVATAR_HOST: string = 'http://tb.himg.baidu.com';

/**
 * 根据 portrait 标识符拼接完整头像 URL。
 *
 * @param portrait 百度用户头像标识符（不含域名）
 * @param size 尺寸：'s'=小头像(55x55) / 'm'=中头像 / 'l'=大头像，默认 'm'
 * @returns 完整头像 URL；portrait 为空时返回空字符串
 */
export function getAvatarUrl(portrait: string, size: AvatarSize = 'm'): string {
  // 空字符串直接返回
  if (portrait.length === 0) {
    return '';
  }
  // 已是完整 URL（http/https 开头）原样返回
  if (portrait.startsWith('http://') || portrait.startsWith('https://')) {
    return portrait;
  }
  // 清洗：含 "?" 时去掉末尾 13 字符（对齐 aiotieba profile/_classdef.py:96-97）
  let cleaned: string = portrait;
  if (cleaned.includes('?')) {
    cleaned = cleaned.slice(0, Math.max(0, cleaned.length - 13));
  }
  if (cleaned.length === 0) {
    return '';
  }
  // 按尺寸选择路径
  let pathSegment: string;
  if (size === 's') {
    pathSegment = 'portraitn';
  } else if (size === 'l') {
    pathSegment = 'portraith';
  } else {
    pathSegment = 'portrait';
  }
  return `${AVATAR_HOST}/sys/${pathSegment}/item/${cleaned}`;
}
