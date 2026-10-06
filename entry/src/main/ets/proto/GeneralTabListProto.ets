// GeneralTabList protobuf 编解码（完整版吧内页面通用 Tab 切换）
// 字段编号对齐 references/protobuf/tbclient.protobuf-main/proto/GeneralTabList/DataReq.proto
// wire format 编解码复用 ProtoWire.ets
//
// 接口：POST /c/f/frs/generalTabList?cmd=309622
// 与 FrsPage（cmd=301001）是独立接口，不复用

import { ThreadInfo, PageData, FrsTabInfo } from '../model/ForumModels';
import { ProtoWriter } from './ProtoWire';
import { STABLE_VERSION } from '../net/TiebaHttpClient';

// ==================== GeneralTabList 请求编码 ====================

/** GeneralTabList 请求参数 */
export interface IGeneralTabListReqParams {
  /** Tab ID（来自 FrsTabInfo.tabId） */
  tabId: number;
  /** Tab 类型（来自 FrsTabInfo.tabType） */
  tabType: number;
  /** Tab 名称（来自 FrsTabInfo.tabName） */
  tabName: string;
  /** 是否通用 Tab（来自 FrsTabInfo.isGeneralTab） */
  isGeneralTab: number;
  /** 是否默认 Tab（来自 FrsTabInfo.isDefault） */
  isDefault: number;
  /** 吧 ID（forum_id，来自 ForumInfo.id） */
  forumId: number;
  /** 页码，从 1 开始 */
  pn: number;
  /** 每页条数，默认 30 */
  rn: number;
  /** 排序方式（对齐 FrsPage sortType：1=按发布 6=按回复） */
  sortType: number;
  /** 客户端版本号 */
  clientVersion: string;
  /** 上次请求最后一条 thread 的 ID（用于翻页，首次为 0） */
  lastThreadId: number;
}

/**
 * 编码 CommonReq（对齐 CommonReq.proto）
 * 复用 FrsPage 的 CommonReq 结构：_client_type + _client_version
 */
function encodeCommonReq(writer: ProtoWriter, params: IGeneralTabListReqParams): void {
  writer.writeInt32(1, 2);                       // _client_type = 2
  writer.writeString(2, params.clientVersion);    // _client_version
}

/** 编码 DataReq（对齐 GeneralTabList/DataReq.proto） */
function encodeDataReq(params: IGeneralTabListReqParams): Uint8Array {
  const writer = new ProtoWriter();
  // 字段 1：common（CommonReq message）
  const commonWriter = new ProtoWriter();
  encodeCommonReq(commonWriter, params);
  writer.writeMessage(1, commonWriter.finish());

  // 字段 2-14：对齐 DataReq.proto 字段编号
  // forum_id 字段类型为 int64，但实际值在 32 位范围内（贴吧 fid 通常 < 10^7）
  // 直接用 writeInt32 编码：内部 writeTag(field, wireVarint) + writeVarint(value)
  // protobuf wire format 上 int32 / int64 都是 varint，解码端按 int64 解析无副作用
  writer.writeInt32(2, params.tabId);             // tab_id
  writer.writeInt32(3, params.forumId);            // forum_id (int64，实际值在 32 位范围内)
  writer.writeInt32(4, params.pn);                 // pn
  writer.writeInt32(5, params.rn);                 // rn
  writer.writeInt32(10, params.isDefault);         // is_default_navtab
  writer.writeString(11, params.tabName);         // tab_name
  writer.writeInt32(12, params.isGeneralTab);     // is_general_tab
  writer.writeInt32(13, params.sortType);          // sort_type
  writer.writeInt32(14, params.tabType);           // tab_type

  return writer.finish();
}

/** 编码 GeneralTabListReqIdl 顶层（对齐 GeneralTabListReqIdl.proto） */
export function encodeGeneralTabListReq(params: IGeneralTabListReqParams): Uint8Array {
  const writer = new ProtoWriter();
  const dataBytes = encodeDataReq(params);
  writer.writeMessage(1, dataBytes);  // data
  return writer.finish();
}

// ==================== GeneralTabList 响应解码 ====================

/** GeneralTabList 解析结果 */
export class GeneralTabListResult {
  threads: PageData<ThreadInfo> = new PageData<ThreadInfo>();
}
