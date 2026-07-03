// PbFloor 楼中楼 protobuf 编解码（issue #73）
// 字段编号对齐 aiotieba api/get_comments/protobuf/PbFloorReqIdl.proto + PbFloorResIdl.proto
// 端点 POST /c/f/pb/floor?cmd=302002（multipart protobuf）
// 分页：pn 页码（从 1 开始），响应 Page.has_more = current_page < total_page
// SubPostList 字段对齐 aiotieba api/_protobuf/SubPostList.proto

import { SubPostInfo, ContentFragment, ContentFragmentType, MediaInfo } from '../model/ForumModels';
import { ProtoWriter, ProtoReader } from './ProtoWire';
import { STABLE_VERSION } from '../net/TiebaHttpClient';
import { decodePostContent, decodeUser } from './PbPageProto';

// ==================== PbFloor 请求编码 ====================

/** PbFloor 请求参数 */
export interface IPbFloorReqParams {
  /** 主题帖 tid（kz） */
  tid: number;
  /** 楼层 pid（要查询楼中楼的楼层 id） */
  pid: number;
  /** 页码（pn），从 1 开始 */
  pn: number;
  /** 楼中楼 spid（用于楼中楼的楼中楼场景，默认 0 = 加载该楼层下所有楼中楼） */
  spid?: number;
}

/** PbFloor 接口返回结果 */
export class PbFloorResult {
  /** 楼中楼列表 */
  subPosts: SubPostInfo[] = [];
  /** 当前页码 */
  currentPage: number = 1;
  /** 总页数 */
  totalPages: number = 1;
  /** 是否有更多（current_page < total_page） */
  hasMore: boolean = false;
}

/**
 * 编码 CommonReq（对齐 aiotieba get_comments/_api.py:20-21）
 * 仅传 _client_type + _client_version（公开读 API 不传 BDUSS，对齐 PbPage）
 */
function encodeCommonReq(writer: ProtoWriter): void {
  writer.writeInt32(1, 2);                    // _client_type = 2
  writer.writeString(2, STABLE_VERSION);      // _client_version
}

/**
 * 编码 PbFloorReqIdl 顶层
 * 字段编号对齐 PbFloorReqIdl.proto DataReq:
 *   kz=1(int64) / pid=2(int64) / spid=3(int64) / pn=4(int32) / common=9
 */
export function encodePbFloorReq(params: IPbFloorReqParams): Uint8Array {
  const writer = new ProtoWriter();

  // 先编码 data 内部
  const dataWriter = new ProtoWriter();
  // common（field 9）
  const commonWriter = new ProtoWriter();
  encodeCommonReq(commonWriter);
  dataWriter.writeMessage(9, commonWriter.finish());
  // kz（field 1，int64 = wire type 0 varint）
  if (params.tid > 0) {
    dataWriter.writeTag(1, 0);
    dataWriter.writeVarint(params.tid);
  }
  // pid（field 2，int64）- 加载楼层楼中楼时传 pid
  if (params.pid > 0) {
    dataWriter.writeTag(2, 0);
    dataWriter.writeVarint(params.pid);
  }
  // spid（field 3，int64）- 加载楼中楼的楼中楼时传 spid，默认 0 不编码
  if (params.spid !== undefined && params.spid > 0) {
    dataWriter.writeTag(3, 0);
    dataWriter.writeVarint(params.spid);
  }
  // pn（field 4，int32）
  dataWriter.writeInt32(4, params.pn);

  // 顶层 data（field 1）
  writer.writeMessage(1, dataWriter.finish());
  return writer.finish();
}

// ==================== PbFloor 响应解码 ====================

/**
 * 解析 Page message（field 编号对齐 Page.proto）
 * 字段：page_size=1 / current_page=3 / total_count=4 / total_page=5 / has_more=6 / has_prev=7
 */
function decodePage(reader: ProtoReader, result: PbFloorResult): void {
  while (!reader.isEnd()) {
    const tag = reader.readTag();
    switch (tag.fieldNumber) {
      case 3:  // current_page
        result.currentPage = reader.readVarint();
        break;
      case 5:  // total_page
        result.totalPages = reader.readVarint();
        break;
      default:
        reader.skipField(tag.wireType);
        break;
    }
  }
  // has_more = current_page < total_page（对齐 aiotieba Page_c.has_more 计算）
  result.hasMore = result.currentPage < result.totalPages;
}

/**
 * 解析 SubPostList message（field 编号对齐 SubPostList.proto）
 * 字段：id=1 / content=2(repeated PbContent) / time=3 / author_id=4 / title=5 /
 *      floor=6 / author=7(User) / is_giftpost=8 / agree=9(Agree) / location=10 / is_fake_top=11
 */
function decodeSubPostList(reader: ProtoReader, tid: number, pid: number): SubPostInfo {
  const subPost = new SubPostInfo();
  subPost.tid = tid;
  subPost.pid = pid;
  let authorId: number = 0;

  while (!reader.isEnd()) {
    const tag = reader.readTag();
    switch (tag.fieldNumber) {
      case 1:   // id（楼中楼 spid）
        subPost.spid = reader.readVarint();
        break;
      case 2: {  // content（repeated PbContent）- 复用 PbPageProto.decodePostContent
        const contentReader = reader.readMessage();
        // 楼中楼无独立 mediaList，传空数组（图片碎片仍会渲染，但不入 mediaList 块）
        const emptyMedia: MediaInfo[] = [];
        const frags: ContentFragment[] = decodePostContent(contentReader, emptyMedia);
        // 合并 fragments 到 subPost.fragments
        for (let i = 0; i < frags.length; i++) {
          subPost.fragments.push(frags[i]);
        }
        break;
      }
      case 3:   // time（创建时间戳，秒）
        subPost.createTime = reader.readVarint();
        break;
      case 4:   // author_id
        authorId = reader.readVarint();
        break;
      case 5:   // title
        subPost.title = reader.readString();
        break;
      case 6:   // floor
        subPost.floor = reader.readVarint();
        break;
      case 7: {  // author（User message）
        const authorReader = reader.readMessage();
        subPost.author = decodeUser(authorReader);
        break;
      }
      case 9: {  // agree（Agree: agree_num=1, disagree_num=4）
        const agreeReader = reader.readMessage();
        while (!agreeReader.isEnd()) {
          const agreeTag = agreeReader.readTag();
          if (agreeTag.fieldNumber === 1) {        // agree_num
            subPost.agreeNum = agreeReader.readVarint();
          } else if (agreeTag.fieldNumber === 4) { // disagree_num
            subPost.disagreeNum = agreeReader.readVarint();
          } else {
            agreeReader.skipField(agreeTag.wireType);
          }
        }
        break;
      }
      default:
        reader.skipField(tag.wireType);
        break;
    }
  }

  // 拼接 content 文本（用于复制/搜索场景，对齐 PostInfo.content 拼接策略）
  let contentText: string = '';
  for (let i = 0; i < subPost.fragments.length; i++) {
    const frag: ContentFragment = subPost.fragments[i];
    // 包含 TEXT/LINK/AT 的 text（可读文本），不包含 EMOJI（text 是 id 非可读）
    if (frag.type === ContentFragmentType.TEXT
        || frag.type === ContentFragmentType.LINK
        || frag.type === ContentFragmentType.AT) {
      contentText += frag.text;
    }
  }
  subPost.content = contentText;

  // 若 author 内嵌未提供，authorId 仅作 fallback 标记（不查询 users map，简化）
  if (subPost.author.uid === 0 && authorId > 0) {
    subPost.author.uid = authorId;
  }
  return subPost;
}

/**
 * 解析 PbFloorResIdl 顶层
 * 结构：error (field 1) + data (field 2)
 * data 内：page=1 / post=3 / subpost_list=4(repeated SubPostList) / thread=5 / forum=6
 */
export function decodePbFloorRes(bytes: Uint8Array, tid: number, pid: number): PbFloorResult {
  const reader = new ProtoReader(bytes);
  const result = new PbFloorResult();

  while (!reader.isEnd()) {
    const tag = reader.readTag();
    if (tag.fieldNumber === 1) {
      // error
      const errReader = reader.readMessage();
      let errorNo: number = 0;
      let errorMsg: string = '';
      while (!errReader.isEnd()) {
        const errTag = errReader.readTag();
        if (errTag.fieldNumber === 1) {        // errorno
          errorNo = errReader.readVarint();
        } else if (errTag.fieldNumber === 2) { // errmsg
          errorMsg = errReader.readString();
        } else {
          errReader.skipField(errTag.wireType);
        }
      }
      if (errorNo !== 0) {
        throw new Error(`获取楼中楼失败 [${errorNo}]: ${errorMsg}`);
      }
    } else if (tag.fieldNumber === 2) {
      // data
      const dataReader = reader.readMessage();
      while (!dataReader.isEnd()) {
        const dataTag = dataReader.readTag();
        if (dataTag.fieldNumber === 1) {
          // page
          const pageReader = dataReader.readMessage();
          decodePage(pageReader, result);
        } else if (dataTag.fieldNumber === 4) {
          // subpost_list（repeated SubPostList）
          const subReader = dataReader.readMessage();
          const subPost = decodeSubPostList(subReader, tid, pid);
          if (subPost.spid > 0) {
            result.subPosts.push(subPost);
          }
        } else {
          dataReader.skipField(dataTag.wireType);
        }
      }
    } else {
      reader.skipField(tag.wireType);
    }
  }
  return result;
}
