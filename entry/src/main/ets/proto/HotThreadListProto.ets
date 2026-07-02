// HotThreadList 热榜 protobuf 编解码（Phase B Issue #67）
// 字段编号对齐 tbclient.protobuf-main/proto/HotThreadList/*.proto
//   - HotThreadListReqIdl: data=1
//   - DataReq: common=1 / tab_id=2 / tab_code=3
//   - HotThreadListResIdl: error=1 / data=2
//   - DataRes: topic_list=1 (repeated RecomTopicList) / thread_info=2 (repeated ThreadInfo)
//              hot_thread_tab_info=3 (repeated FrsTabInfo)
// wire format 编解码复用 ProtoWire.ets，thread 解码复用 FrsPageProto.decodeThread
// aiotieba 无此 API 实现，对照 tbclient.protobuf-main + TiebaLite-4.0-dev 手写

import { ThreadInfo, UserInfo, HotThreadListResult, HotTopicInfo, HotTabInfo } from '../model/ForumModels';
import { ProtoWriter, ProtoReader } from './ProtoWire';
import { decodeThread } from './FrsPageProto';
import { STABLE_VERSION } from '../net/TiebaHttpClient';

// ==================== HotThreadList 请求编码 ====================

/** HotThreadList 请求参数 */
export interface IHotThreadListReqParams {
  /** Tab 编码，默认 "all" 表示全部 */
  tabCode: string;
}

/**
 * 编码 CommonRequest（field 编号对齐 CommonRequest.proto）
 * 仅传 _client_type + _client_version（对齐原版 buildCommonRequest）
 */
function encodeCommonReq(writer: ProtoWriter): void {
  writer.writeInt32(1, 2);                    // _client_type = 2
  writer.writeString(2, STABLE_VERSION);      // _client_version
}

/**
 * 编码 HotThreadListRequest 顶层（field 1 = data）
 * data 内：common(field 1) + tab_id(field 2, 固定 "1") + tab_code(field 3)
 */
export function encodeHotThreadListReq(params: IHotThreadListReqParams): Uint8Array {
  const writer = new ProtoWriter();

  // 先编码 data 内部内容
  const dataWriter = new ProtoWriter();
  // common（field 1）
  const commonWriter = new ProtoWriter();
  encodeCommonReq(commonWriter);
  dataWriter.writeMessage(1, commonWriter.finish());
  // tab_id（field 2，固定 "1"，对齐原 app MixedTiebaApiImpl.kt:1047）
  dataWriter.writeString(2, '1');
  // tab_code（field 3，如 "all"）
  dataWriter.writeString(3, params.tabCode);

  // 顶层 data（field 1）
  writer.writeMessage(1, dataWriter.finish());
  return writer.finish();
}

// ==================== HotThreadList 响应解码 ====================

/**
 * 解析 RecomTopicList（话题榜条目）
 * 字段：topic_id=1 / topic_name=2 / type=3 / discuss_num=4 / tag=5 /
 *      topic_desc=6 / topic_pic=7 / update_time=8 / author=9 / media=10 / is_video_topic=11
 * 注意：无 rank 字段，排名用 topic_list 数组 index 推导
 */
function decodeTopic(reader: ProtoReader): HotTopicInfo {
  const topic = new HotTopicInfo();
  while (!reader.isEnd()) {
    const tag = reader.readTag();
    switch (tag.fieldNumber) {
      case 1:   // topic_id（uint64，转 number）
        topic.topicId = reader.readVarint();
        break;
      case 2:   // topic_name
        topic.topicName = reader.readString();
        break;
      case 4:   // discuss_num（uint64）
        topic.discussNum = reader.readVarint();
        break;
      case 5:   // tag（位掩码：1=热 2=新）
        topic.tag = reader.readVarint();
        break;
      case 6:   // topic_desc
        topic.topicDesc = reader.readString();
        break;
      case 7:   // topic_pic
        topic.topicPic = reader.readString();
        break;
      default:
        // type=3 / update_time=8 / author=9 / media=10 / is_video_topic=11 暂不使用，跳过
        reader.skipField(tag.wireType);
        break;
    }
  }
  return topic;
}

/**
 * 解析 FrsTabInfo（子 Tab 信息，仅提取 tab_id/tab_name/tab_code）
 * 字段：tab_id=1 / tab_type=2 / tab_name=3 / ... / tab_code=8 / ...
 */
function decodeTabInfo(reader: ProtoReader): HotTabInfo {
  const tab = new HotTabInfo();
  while (!reader.isEnd()) {
    const tag = reader.readTag();
    switch (tag.fieldNumber) {
      case 1:   // tab_id
        tab.tabId = reader.readVarint();
        break;
      case 3:   // tab_name
        tab.tabName = reader.readString();
        break;
      case 8:   // tab_code
        tab.tabCode = reader.readString();
        break;
      default:
        // tab_type=2 / tab_url=4 / tab_gid=5 / ... 暂不使用，跳过
        reader.skipField(tag.wireType);
        break;
    }
  }
  return tab;
}

/**
 * 解析 HotThreadListResponse 顶层
 * 结构：error (field 1) + data (field 2)
 * data 内：topic_list (field 1, repeated) + thread_info (field 2, repeated)
 *          + hot_thread_tab_info (field 3, repeated)
 */
export function decodeHotThreadListRes(bytes: Uint8Array): HotThreadListResult {
  const reader = new ProtoReader(bytes);
  const result = new HotThreadListResult();
  // HotThreadList 响应无 user_list，传空 map，author 由 decodeThread 的 field 18 内嵌解析
  const emptyUsers = new Map<number, UserInfo>();

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
        throw new Error(`获取热榜失败 [${errorNo}]: ${errorMsg}`);
      }
    } else if (tag.fieldNumber === 2) {
      // data
      const dataReader = reader.readMessage();
      while (!dataReader.isEnd()) {
        const dataTag = dataReader.readTag();
        if (dataTag.fieldNumber === 1) {
          // topic_list（repeated RecomTopicList）
          const topicReader = dataReader.readMessage();
          result.topicList.push(decodeTopic(topicReader));
        } else if (dataTag.fieldNumber === 2) {
          // thread_info（repeated ThreadInfo，复用 decodeThread）
          const threadReader = dataReader.readMessage();
          result.threadList.push(decodeThread(threadReader, emptyUsers, ''));
        } else if (dataTag.fieldNumber === 3) {
          // hot_thread_tab_info（repeated FrsTabInfo）
          const tabReader = dataReader.readMessage();
          result.tabList.push(decodeTabInfo(tabReader));
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
