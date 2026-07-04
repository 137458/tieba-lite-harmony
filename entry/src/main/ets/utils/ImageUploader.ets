import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { TiebaHttpClient, MultipartTextField, MultipartFileField } from '../net/TiebaHttpClient';
import { ResponseData } from '../net/HttpClient';
import { CryptoUtil } from './CryptoUtil';

/**
 * #74 图片上传工具（对齐 Android ImageUploader.kt）
 *
 * 实现：
 *   1. 压缩：JPEG quality=95，普通图 5MB 阈值，原图 10MB 阈值，超限缩放至 1080P 长边
 *   2. 分块上传：每块 512000 字节（非 524288），chunkNo 从 1 开始，串行不并发
 *   3. 只取最后一块响应的 picId + picInfo.originPic.width/height
 *
 * 关键约束（Android ImageUploader.kt 必须严格遵循）：
 *   - 分块大小固定 512000 字节
 *   - chunkNo 从 1 开始，最后一块 isFinish="1"
 *   - resourceId = fileMd5 + "512000"（字符串拼接，所有块同值）
 *   - width/height 字段填原始解码宽高（非压缩后）
 *   - size 字段填压缩后文件总字节数
 *   - groupId 固定 "1"，is_bjh 固定 "0"，alt 固定 "json"，pic_water_type 默认 "2"
 *   - 串行上传，不并发不重试，任一块失败整体抛异常
 */

/** 分块大小（对齐 Android ImageUploader.DEFAULT_CHUNK_SIZE = 512000，非 524288） */
const CHUNK_SIZE: number = 512000;
/** 普通图上限（5MB，对齐 Android IMAGE_MAX_SIZE） */
const IMAGE_MAX_SIZE: number = 5242880;
/** 原图上限（10MB，对齐 Android ORIGIN_IMAGE_MAX_SIZE） */
const ORIGIN_IMAGE_MAX_SIZE: number = 10485760;
/** 缩放目标长边像素（对齐 Android 1080P） */
const TARGET_LONG_EDGE: number = 1080;
/** JPEG 初始质量（对齐 Android ImageUtil.compressImage quality=95） */
const INITIAL_QUALITY: number = 95;
/** JPEG 最低质量（避免极端大图无限循环） */
const MIN_QUALITY: number = 30;
/** 质量降级步进（每次降 10） */
const QUALITY_STEP: number = 10;
/** 默认水印类型："2"=吧名水印（对齐 Android PIC_WATER_TYPE_FORUM_NAME 默认值） */
const PIC_WATER_TYPE_DEFAULT: string = '2';
/** 图片上传端点（对齐 Android OfficialTiebaApi.uploadPicture） */
const UPLOAD_PICTURE_PATH: string = '/c/s/uploadPicture';
/** 文件字段名（对齐 Android ImageUploader：name="chunk", filename="file"） */
const FILE_FIELD_NAME: string = 'chunk';
const FILE_FIELD_FILENAME: string = 'file';
const FILE_CONTENT_TYPE: string = 'image/jpeg';

/**
 * 上传图片结果（仅含回帖拼接必需字段）
 * 用于 #(pic,picId,width,height) 文本拼接
 */
export interface UploadedPicInfo {
  /** 图片 ID（最后一块响应的 picId） */
  picId: string;
  /** 原图宽（来自 picInfo.originPic.width） */
  width: number;
  /** 原图高（来自 picInfo.originPic.height） */
  height: number;
}

/** /c/s/uploadPicture 响应（对齐 Android UploadPictureResultBean） */
interface UploadPictureResponse {
  // error_code 运行时可能为数字或字符串（JSON.parse 不保证类型），声明为联合类型
  error_code?: number | string;
  error_msg?: string;
  /** 续传标识（每块都返回，本项目不做断点续传） */
  resourceId?: string;
  /** 当前块号（字符串形式） */
  chunkNo?: string;
  /** 图片 ID（仅最后一块返回非空） */
  picId?: string;
  /** 图片信息（仅最后一块返回非空） */
  picInfo?: PicInfoResponse;
}

/** picInfo 子对象（对齐 Android PicInfo） */
interface PicInfoResponse {
  originPic?: PicInfoItem;
  bigPic?: PicInfoItem;
  smallPic?: PicInfoItem;
}

/** picInfo 单个尺寸项（对齐 Android PicInfoItem） */
interface PicInfoItem {
  width?: string;
  height?: string;
  type?: string;
  picUrl?: string;
}

/** 压缩结果（含字节数据 + 原始宽高） */
interface CompressedImage {
  /** JPEG 编码后的字节数据 */
  data: ArrayBuffer;
  /** 原始解码宽（用于 multipart width 字段 + 回帖 #(pic,...,w,h)） */
  originalWidth: number;
  /** 原始解码高（用于 multipart height 字段 + 回帖 #(pic,...,w,h)） */
  originalHeight: number;
}

export class ImageUploader {
  /**
   * 上传单张图片（压缩 + 分块上传）
   * 对齐 Android ImageUploader.uploadSinglePicture
   *
   * @param uri photoAccessHelper 返回的图片 uri
   * @param forumName 贴吧名（kw），用于 forum_name + small_flow_fname 字段
   * @param isOriginImage true=原图模式（10MB 阈值，不压缩），false=普通模式（5MB 阈值，压缩）
   * @returns UploadedPicInfo（picId + 原始宽高）
   */
  static async uploadSinglePicture(
    uri: string,
    forumName: string,
    isOriginImage: boolean
  ): Promise<UploadedPicInfo> {
    // 1) 压缩（同时拿到原始宽高）
    const compressed: CompressedImage = await ImageUploader.compressImage(uri, isOriginImage);
    const compressedBytes: Uint8Array = new Uint8Array(compressed.data);

    // 2) 校验大小
    const maxSize: number = isOriginImage ? ORIGIN_IMAGE_MAX_SIZE : IMAGE_MAX_SIZE;
    if (compressedBytes.length > maxSize) {
      throw new Error(`图片压缩后仍超过限制：${compressedBytes.length} > ${maxSize}`);
    }

    // 3) 计算文件 MD5（用于 resourceId）
    const fileMd5: string = await ImageUploader.computeMd5(compressedBytes);

    // 4) 计算分块数
    // 整除时 totalChunkNum = fileLength / CHUNK_SIZE；非整除时 +1
    const fileLength: number = compressedBytes.length;
    const isMultipleChunkSize: boolean = (fileLength % CHUNK_SIZE) === 0;
    let totalChunkNum: number = Math.floor(fileLength / CHUNK_SIZE);
    if (!isMultipleChunkSize) {
      totalChunkNum += 1;
    }
    // 文件为空时至少 1 块（理论上不会发生，已压缩出字节数据）
    if (totalChunkNum < 1) {
      totalChunkNum = 1;
    }

    // 5) 串行分块上传，只取最后一块响应
    const resourceId: string = `${fileMd5}${CHUNK_SIZE}`;
    let lastResponse: UploadPictureResponse | null = null;
    for (let chunkIdx = 0; chunkIdx < totalChunkNum; chunkIdx++) {
      const isFinish: boolean = chunkIdx === totalChunkNum - 1;
      // 当前块字节数：最后一块可能不足 CHUNK_SIZE
      const curChunkSize: number = isFinish
        ? (isMultipleChunkSize ? CHUNK_SIZE : (fileLength % CHUNK_SIZE))
        : CHUNK_SIZE;
      // 切片当前块字节
      const chunkBytes: Uint8Array = compressedBytes.subarray(
        chunkIdx * CHUNK_SIZE,
        chunkIdx * CHUNK_SIZE + curChunkSize
      );

      const response: UploadPictureResponse = await ImageUploader.uploadSingleChunk(
        chunkBytes,
        chunkIdx + 1,                // chunkNo 从 1 开始
        isFinish,
        resourceId,
        forumName,
        isOriginImage,
        fileLength,
        compressed.originalWidth,
        compressed.originalHeight
      );
      lastResponse = response;
    }

    if (lastResponse === null) {
      throw new Error('图片上传失败：未收到任何响应');
    }

    // 6) 解析最后一块响应，提取 picId + 原图宽高
    // P1 修复：error_code 缺失时默认按 '0' 处理；error_code 非 0 但有 picId 也视为成功（防御性）
    const errorCode: string = String(lastResponse.error_code ?? '0');
    const hasPicId: boolean = !!lastResponse.picId && lastResponse.picId.length > 0;
    if (errorCode !== '0' && !hasPicId) {
      const errMsg: string = lastResponse.error_msg || '图片上传失败';
      throw new Error(`图片上传失败: code=${errorCode}, msg=${errMsg}`);
    }
    if (!hasPicId || !lastResponse.picInfo || !lastResponse.picInfo.originPic) {
      throw new Error('图片上传失败：响应缺少 picId 或 picInfo.originPic');
    }
    const originPic: PicInfoItem = lastResponse.picInfo.originPic;
    const width: number = originPic.width ? parseInt(originPic.width, 10) : 0;
    const height: number = originPic.height ? parseInt(originPic.height, 10) : 0;

    // hasPicId 检查已确保 picId 非空非 undefined，此处用 as string 收窄类型
    return {
      picId: lastResponse.picId as string,
      width: width,
      height: height
    };
  }

  /**
   * 多图顺序上传（对齐 Android ImageUploader.uploadImages，串行不并发）
   * 任一张失败则整体抛异常（已上传的图片不会撤销，但服务端未关联到回帖，无副作用）
   *
   * @param uris photoAccessHelper 返回的图片 uri 数组
   * @param forumName 贴吧名
   * @param isOriginImage true=原图模式
   * @returns UploadedPicInfo 数组（顺序与输入一致）
   */
  static async uploadImages(
    uris: string[],
    forumName: string,
    isOriginImage: boolean
  ): Promise<UploadedPicInfo[]> {
    const results: UploadedPicInfo[] = [];
    for (let i = 0; i < uris.length; i++) {
      const result: UploadedPicInfo = await ImageUploader.uploadSinglePicture(
        uris[i], forumName, isOriginImage
      );
      results.push(result);
    }
    return results;
  }

  /**
   * 压缩图片为 JPEG ArrayBuffer
   * 对齐 Android ImageUploader.compressImage：
   *   - 原图模式 + 文件 ≤10MB：零压缩，直接读原始字节
   *   - 普通模式 或 原图超 10MB：
   *     1) 解码全尺寸 → JPEG q=95
   *     2) 仍超 maxSize：长边缩到 1080px → 再 JPEG q=95
   *     3) 仍超：循环降质量直到 ≤ maxSize 或 quality ≤ 30
   *
   * @param uri 图片 uri（picker 返回）
   * @param isOriginImage true=原图模式（10MB 阈值）
   */
  static async compressImage(uri: string, isOriginImage: boolean): Promise<CompressedImage> {
    // Step 1: 创建 ImageSource 并获取原始宽高
    const imageSource: image.ImageSource = image.createImageSource(uri);
    let pixelMap: image.PixelMap | null = null;
    let packer: image.ImagePacker | null = null;
    try {
      const info: image.ImageInfo = await imageSource.getImageInfo();
      const originalWidth: number = info.size.width;
      const originalHeight: number = info.size.height;
      if (originalWidth <= 0 || originalHeight <= 0) {
        throw new Error('图片宽高不正确');
      }

      const maxSize: number = isOriginImage ? ORIGIN_IMAGE_MAX_SIZE : IMAGE_MAX_SIZE;

      // Step 2: 原图模式 + 文件未超 10MB → 零压缩，直接读原始字节
      if (isOriginImage) {
        const fileBytes: ArrayBuffer = await ImageUploader.readFileBytes(uri);
        if (fileBytes.byteLength <= ORIGIN_IMAGE_MAX_SIZE) {
          return {
            data: fileBytes,
            originalWidth: originalWidth,
            originalHeight: originalHeight
          };
        }
        // 超 10MB 走压缩路径
      }

      // Step 3: 解码为 PixelMap（editable=true 以便 scale）
      pixelMap = await imageSource.createPixelMap({
        editable: true,
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888
      });

      // Step 4: 第一遍 JPEG q=95
      packer = image.createImagePacker();
      let data: ArrayBuffer = await packer.packing(pixelMap, {
        format: 'image/jpeg',
        quality: INITIAL_QUALITY
      });

      // Step 5: 仍超 maxSize → 长边缩到 1080px
      if (data.byteLength > maxSize) {
        const longEdge: number = Math.max(originalWidth, originalHeight);
        if (longEdge > TARGET_LONG_EDGE) {
          const ratio: number = TARGET_LONG_EDGE / longEdge;
          await pixelMap.scale(ratio, ratio);
          data = await packer.packing(pixelMap, {
            format: 'image/jpeg',
            quality: INITIAL_QUALITY
          });
        }
      }

      // Step 6: 仍超 → 循环降质量
      let quality: number = INITIAL_QUALITY;
      while (data.byteLength > maxSize && quality > MIN_QUALITY) {
        quality -= QUALITY_STEP;
        data = await packer.packing(pixelMap, {
          format: 'image/jpeg',
          quality: quality
        });
      }

      return {
        data: data,
        originalWidth: originalWidth,
        originalHeight: originalHeight
      };
    } finally {
      if (pixelMap !== null) {
        pixelMap.release();
      }
      if (packer !== null) {
        packer.release();
      }
      imageSource.release();
    }
  }

  /**
   * 上传单个分块
   * 对齐 Android ImageUploader + OfficialTiebaApi.uploadPicture
   *
   * 字段顺序（对齐 Android addFormDataPart 调用顺序）：
   *   alt → chunkNo → forum_name → groupId → height → isFinish → is_bjh →
   *   pic_water_type → resourceId → saveOrigin → size → small_flow_fname → width → chunk(file)
   */
  private static async uploadSingleChunk(
    chunkBytes: Uint8Array,
    chunkNo: number,
    isFinish: boolean,
    resourceId: string,
    forumName: string,
    isOriginImage: boolean,
    totalSize: number,
    width: number,
    height: number
  ): Promise<UploadPictureResponse> {
    const textFields: MultipartTextField[] = [];
    textFields.push({ name: 'alt', value: 'json' });
    textFields.push({ name: 'chunkNo', value: String(chunkNo) });
    if (forumName.length > 0) {
      textFields.push({ name: 'forum_name', value: forumName });
    }
    textFields.push({ name: 'groupId', value: '1' });
    textFields.push({ name: 'height', value: String(height) });
    textFields.push({ name: 'isFinish', value: isFinish ? '1' : '0' });
    textFields.push({ name: 'is_bjh', value: '0' });
    textFields.push({ name: 'pic_water_type', value: PIC_WATER_TYPE_DEFAULT });
    textFields.push({ name: 'resourceId', value: resourceId });
    textFields.push({ name: 'saveOrigin', value: isOriginImage ? '1' : '0' });
    textFields.push({ name: 'size', value: String(totalSize) });
    if (forumName.length > 0) {
      textFields.push({ name: 'small_flow_fname', value: forumName });
    }
    textFields.push({ name: 'width', value: String(width) });

    const fileField: MultipartFileField = {
      name: FILE_FIELD_NAME,
      filename: FILE_FIELD_FILENAME,
      contentType: FILE_CONTENT_TYPE,
      data: chunkBytes
    };

    const client: TiebaHttpClient = TiebaHttpClient.getInstance();
    const response: ResponseData = await client.postMultipart(
      UPLOAD_PICTURE_PATH, textFields, fileField
    );

    if (response.statusCode !== 200) {
      throw new Error(`图片上传 HTTP 失败: status=${response.statusCode}`);
    }

    // P1 修复：校验响应数据类型 + JSON.parse 包 try-catch，避免不友好异常
    const responseText: string = response.data as string;
    if (typeof responseText !== 'string' || responseText.length === 0) {
      throw new Error(`图片上传响应格式异常: statusCode=${response.statusCode}, dataType=${typeof response.data}`);
    }
    let parsed: UploadPictureResponse;
    try {
      parsed = JSON.parse(responseText) as UploadPictureResponse;
    } catch (e) {
      throw new Error(`图片上传响应解析失败: ${responseText.substring(0, 200)}`);
    }
    return parsed;
  }

  /**
   * 读取图片 uri 全部字节为 ArrayBuffer
   * 用 fs.openSync + statSync + readSync（picker uri 自带只读临时权限）
   */
  private static async readFileBytes(uri: string): Promise<ArrayBuffer> {
    const file: fs.File = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    try {
      const stat: fs.Stat = fs.statSync(file.fd);
      const buffer: ArrayBuffer = new ArrayBuffer(stat.size);
      let readLen: number = 0;
      while (readLen < stat.size) {
        const ret: number = fs.readSync(file.fd, buffer, {
          offset: readLen,
          length: stat.size - readLen
        });
        if (ret <= 0) {
          break;
        }
        readLen += ret;
      }
      // P0 修复：读取不完整时抛异常，避免 MD5 基于部分数据计算 + size 字段与实际字节不匹配
      if (readLen !== stat.size) {
        throw new Error(`图片读取不完整: ${readLen}/${stat.size}`);
      }
      return buffer;
    } finally {
      fs.closeSync(file);
    }
  }

  /**
   * 计算字节数组的 MD5（用于 resourceId 拼接）
   * 复用 CryptoUtil.md5Bytes（项目已有实现，避免重复造轮子）
   */
  private static async computeMd5(data: Uint8Array): Promise<string> {
    const md5Bytes: Uint8Array = await CryptoUtil.md5Bytes(data);
    return CryptoUtil.bytesToHex(md5Bytes);
  }
}
