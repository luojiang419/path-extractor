#include "special_thumbnail_channel.h"

#include <flutter/binary_messenger.h>

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <limits>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

#include <winsock2.h>
#include <ShObjIdl.h>
#include <wincodec.h>
#include <wrl/client.h>

#include "libraw/libraw.h"
#include "utils.h"

namespace {

using Microsoft::WRL::ComPtr;

constexpr size_t kPsdThumbnailHeaderSize = 28;
constexpr size_t kMaxPsdFileSizeBytes = 128u * 1024u * 1024u;

uint16_t ReadBigEndian16(const uint8_t* buffer) {
  return static_cast<uint16_t>((buffer[0] << 8) | buffer[1]);
}

uint32_t ReadBigEndian32(const uint8_t* buffer) {
  return (static_cast<uint32_t>(buffer[0]) << 24) |
         (static_cast<uint32_t>(buffer[1]) << 16) |
         (static_cast<uint32_t>(buffer[2]) << 8) |
         static_cast<uint32_t>(buffer[3]);
}

bool ReadSmallBinaryFile(const std::wstring& path, size_t max_size,
                         std::vector<uint8_t>* bytes) {
  if (bytes == nullptr) {
    return false;
  }

  HANDLE file = ::CreateFileW(path.c_str(), GENERIC_READ,
                              FILE_SHARE_READ | FILE_SHARE_WRITE |
                                  FILE_SHARE_DELETE,
                              nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL,
                              nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    return false;
  }

  LARGE_INTEGER file_size = {};
  const bool got_size = ::GetFileSizeEx(file, &file_size) != FALSE;
  if (!got_size || file_size.QuadPart <= 0 ||
      static_cast<uint64_t>(file_size.QuadPart) > max_size) {
    ::CloseHandle(file);
    return false;
  }

  bytes->resize(static_cast<size_t>(file_size.QuadPart));
  DWORD read_size = 0;
  const bool read_ok =
      ::ReadFile(file, bytes->data(), static_cast<DWORD>(bytes->size()),
                 &read_size, nullptr) != FALSE;
  ::CloseHandle(file);
  if (!read_ok || read_size != static_cast<DWORD>(bytes->size())) {
    bytes->clear();
    return false;
  }

  return true;
}

HRESULT CreateWicFactory(ComPtr<IWICImagingFactory>* factory) {
  if (factory == nullptr) {
    return E_POINTER;
  }

  return ::CoCreateInstance(CLSID_WICImagingFactory, nullptr,
                            CLSCTX_INPROC_SERVER,
                            IID_PPV_ARGS(factory->ReleaseAndGetAddressOf()));
}

HRESULT ScaleBitmapSource(IWICImagingFactory* factory, IWICBitmapSource* source,
                          UINT max_edge,
                          ComPtr<IWICBitmapSource>* scaled_source) {
  if (factory == nullptr || source == nullptr || scaled_source == nullptr) {
    return E_POINTER;
  }

  UINT width = 0;
  UINT height = 0;
  HRESULT hr = source->GetSize(&width, &height);
  if (FAILED(hr)) {
    return hr;
  }

  if (width == 0 || height == 0) {
    return E_FAIL;
  }

  const UINT safe_max_edge = std::max<UINT>(1, max_edge);
  if (width <= safe_max_edge && height <= safe_max_edge) {
    scaled_source->Reset();
    source->AddRef();
    scaled_source->Attach(source);
    return S_OK;
  }

  const double scale =
      std::min(static_cast<double>(safe_max_edge) / width,
               static_cast<double>(safe_max_edge) / height);
  const UINT scaled_width = std::max<UINT>(
      1, static_cast<UINT>(static_cast<double>(width) * scale));
  const UINT scaled_height = std::max<UINT>(
      1, static_cast<UINT>(static_cast<double>(height) * scale));

  ComPtr<IWICBitmapScaler> scaler;
  hr = factory->CreateBitmapScaler(&scaler);
  if (FAILED(hr)) {
    return hr;
  }

  hr = scaler->Initialize(source, scaled_width, scaled_height,
                          WICBitmapInterpolationModeFant);
  if (FAILED(hr)) {
    return hr;
  }

  ComPtr<IWICBitmapSource> bitmap_source;
  hr = scaler.As(&bitmap_source);
  if (FAILED(hr)) {
    return hr;
  }

  *scaled_source = bitmap_source;
  return S_OK;
}

HRESULT ConvertToBgraSource(IWICImagingFactory* factory,
                            IWICBitmapSource* source,
                            ComPtr<IWICBitmapSource>* bgra_source) {
  if (factory == nullptr || source == nullptr || bgra_source == nullptr) {
    return E_POINTER;
  }

  ComPtr<IWICFormatConverter> converter;
  HRESULT hr = factory->CreateFormatConverter(&converter);
  if (FAILED(hr)) {
    return hr;
  }

  hr = converter->Initialize(source, GUID_WICPixelFormat32bppBGRA,
                             WICBitmapDitherTypeNone, nullptr, 0.0,
                             WICBitmapPaletteTypeCustom);
  if (FAILED(hr)) {
    return hr;
  }

  ComPtr<IWICBitmapSource> converted_source;
  hr = converter.As(&converted_source);
  if (FAILED(hr)) {
    return hr;
  }

  *bgra_source = converted_source;
  return S_OK;
}

HRESULT EncodeBitmapSourceToPngBytes(IWICImagingFactory* factory,
                                     IWICBitmapSource* source,
                                     std::vector<uint8_t>* png_bytes) {
  if (factory == nullptr || source == nullptr || png_bytes == nullptr) {
    return E_POINTER;
  }

  ComPtr<IWICBitmapSource> bgra_source;
  HRESULT hr = ConvertToBgraSource(factory, source, &bgra_source);
  if (FAILED(hr)) {
    return hr;
  }

  UINT width = 0;
  UINT height = 0;
  hr = bgra_source->GetSize(&width, &height);
  if (FAILED(hr)) {
    return hr;
  }

  ComPtr<IStream> stream;
  hr = ::CreateStreamOnHGlobal(nullptr, TRUE, &stream);
  if (FAILED(hr)) {
    return hr;
  }

  ComPtr<IWICBitmapEncoder> encoder;
  hr = factory->CreateEncoder(GUID_ContainerFormatPng, nullptr, &encoder);
  if (FAILED(hr)) {
    return hr;
  }

  hr = encoder->Initialize(stream.Get(), WICBitmapEncoderNoCache);
  if (FAILED(hr)) {
    return hr;
  }

  ComPtr<IWICBitmapFrameEncode> frame;
  ComPtr<IPropertyBag2> property_bag;
  hr = encoder->CreateNewFrame(&frame, &property_bag);
  if (FAILED(hr)) {
    return hr;
  }

  hr = frame->Initialize(property_bag.Get());
  if (FAILED(hr)) {
    return hr;
  }

  hr = frame->SetSize(width, height);
  if (FAILED(hr)) {
    return hr;
  }

  WICPixelFormatGUID pixel_format = GUID_WICPixelFormat32bppBGRA;
  hr = frame->SetPixelFormat(&pixel_format);
  if (FAILED(hr)) {
    return hr;
  }

  hr = frame->WriteSource(bgra_source.Get(), nullptr);
  if (FAILED(hr)) {
    return hr;
  }

  hr = frame->Commit();
  if (FAILED(hr)) {
    return hr;
  }

  hr = encoder->Commit();
  if (FAILED(hr)) {
    return hr;
  }

  HGLOBAL global_handle = nullptr;
  hr = ::GetHGlobalFromStream(stream.Get(), &global_handle);
  if (FAILED(hr) || global_handle == nullptr) {
    return FAILED(hr) ? hr : E_FAIL;
  }

  const SIZE_T byte_count = ::GlobalSize(global_handle);
  if (byte_count == 0) {
    return E_FAIL;
  }

  void* locked_memory = ::GlobalLock(global_handle);
  if (locked_memory == nullptr) {
    return E_FAIL;
  }

  const auto* begin = static_cast<const uint8_t*>(locked_memory);
  png_bytes->assign(begin, begin + byte_count);
  ::GlobalUnlock(global_handle);
  return S_OK;
}

std::optional<std::vector<uint8_t>> DecodeImageBufferToPngBytes(
    const uint8_t* encoded_bytes, size_t encoded_size, UINT max_edge) {
  if (encoded_bytes == nullptr || encoded_size == 0 ||
      encoded_size > static_cast<size_t>(std::numeric_limits<DWORD>::max())) {
    return std::nullopt;
  }

  ComPtr<IWICImagingFactory> factory;
  HRESULT hr = CreateWicFactory(&factory);
  if (FAILED(hr)) {
    return std::nullopt;
  }

  ComPtr<IWICStream> stream;
  hr = factory->CreateStream(&stream);
  if (FAILED(hr)) {
    return std::nullopt;
  }

  hr = stream->InitializeFromMemory(const_cast<BYTE*>(encoded_bytes),
                                    static_cast<DWORD>(encoded_size));
  if (FAILED(hr)) {
    return std::nullopt;
  }

  ComPtr<IWICBitmapDecoder> decoder;
  hr = factory->CreateDecoderFromStream(stream.Get(), nullptr,
                                        WICDecodeMetadataCacheOnLoad, &decoder);
  if (FAILED(hr)) {
    return std::nullopt;
  }

  ComPtr<IWICBitmapFrameDecode> frame;
  hr = decoder->GetFrame(0, &frame);
  if (FAILED(hr)) {
    return std::nullopt;
  }

  ComPtr<IWICBitmapSource> scaled_source;
  hr = ScaleBitmapSource(factory.Get(), frame.Get(), max_edge, &scaled_source);
  if (FAILED(hr)) {
    return std::nullopt;
  }

  std::vector<uint8_t> png_bytes;
  hr = EncodeBitmapSourceToPngBytes(factory.Get(), scaled_source.Get(),
                                    &png_bytes);
  if (FAILED(hr) || png_bytes.empty()) {
    return std::nullopt;
  }

  return png_bytes;
}

std::optional<std::vector<uint8_t>> EncodeBgraBitmapToPngBytes(
    const std::vector<uint8_t>& bgra_bytes, UINT width, UINT height,
    UINT max_edge) {
  if (bgra_bytes.empty() || width == 0 || height == 0) {
    return std::nullopt;
  }

  ComPtr<IWICImagingFactory> factory;
  HRESULT hr = CreateWicFactory(&factory);
  if (FAILED(hr)) {
    return std::nullopt;
  }

  ComPtr<IWICBitmap> bitmap;
  const UINT stride = width * 4;
  hr = factory->CreateBitmapFromMemory(
      width, height, GUID_WICPixelFormat32bppBGRA, stride,
      static_cast<UINT>(bgra_bytes.size()),
      const_cast<BYTE*>(bgra_bytes.data()), &bitmap);
  if (FAILED(hr)) {
    return std::nullopt;
  }

  ComPtr<IWICBitmapSource> scaled_source;
  hr = ScaleBitmapSource(factory.Get(), bitmap.Get(), max_edge, &scaled_source);
  if (FAILED(hr)) {
    return std::nullopt;
  }

  std::vector<uint8_t> png_bytes;
  hr = EncodeBitmapSourceToPngBytes(factory.Get(), scaled_source.Get(),
                                    &png_bytes);
  if (FAILED(hr) || png_bytes.empty()) {
    return std::nullopt;
  }

  return png_bytes;
}

std::optional<std::vector<uint8_t>> EncodeHBitmapToPngBytes(HBITMAP bitmap,
                                                             UINT max_edge) {
  if (bitmap == nullptr) {
    return std::nullopt;
  }

  ComPtr<IWICImagingFactory> factory;
  HRESULT hr = CreateWicFactory(&factory);
  if (FAILED(hr)) {
    return std::nullopt;
  }

  ComPtr<IWICBitmap> wic_bitmap;
  hr = factory->CreateBitmapFromHBITMAP(bitmap, nullptr, WICBitmapUseAlpha,
                                        &wic_bitmap);
  if (FAILED(hr)) {
    return std::nullopt;
  }

  ComPtr<IWICBitmapSource> scaled_source;
  hr =
      ScaleBitmapSource(factory.Get(), wic_bitmap.Get(), max_edge, &scaled_source);
  if (FAILED(hr)) {
    return std::nullopt;
  }

  std::vector<uint8_t> png_bytes;
  hr = EncodeBitmapSourceToPngBytes(factory.Get(), scaled_source.Get(),
                                    &png_bytes);
  if (FAILED(hr) || png_bytes.empty()) {
    return std::nullopt;
  }

  return png_bytes;
}

std::optional<std::vector<uint8_t>> TryGetShellThumbnail(
    const std::wstring& path, UINT max_edge) {
  ComPtr<IShellItemImageFactory> image_factory;
  HRESULT hr = ::SHCreateItemFromParsingName(
      path.c_str(), nullptr,
      IID_PPV_ARGS(image_factory.ReleaseAndGetAddressOf()));
  if (FAILED(hr)) {
    return std::nullopt;
  }

  HBITMAP bitmap = nullptr;
  const SIZE size = {static_cast<LONG>(max_edge), static_cast<LONG>(max_edge)};
  hr = image_factory->GetImage(
      size, static_cast<SIIGBF>(SIIGBF_BIGGERSIZEOK | SIIGBF_THUMBNAILONLY),
      &bitmap);
  if (FAILED(hr) || bitmap == nullptr) {
    return std::nullopt;
  }

  auto encoded = EncodeHBitmapToPngBytes(bitmap, max_edge);
  ::DeleteObject(bitmap);
  return encoded;
}

std::optional<std::vector<uint8_t>> EncodeLibRawProcessedImageToPngBytes(
    const libraw_processed_image_t* image, UINT max_edge) {
  if (image == nullptr || image->width == 0 || image->height == 0) {
    return std::nullopt;
  }

  if (image->colors != 1 && image->colors != 3) {
    return std::nullopt;
  }

  if (image->bits != 8 && image->bits != 16) {
    return std::nullopt;
  }

  const size_t channel_count = static_cast<size_t>(image->colors);
  const size_t bytes_per_channel = image->bits == 16 ? 2u : 1u;
  const size_t pixel_count =
      static_cast<size_t>(image->width) * static_cast<size_t>(image->height);
  const size_t required_size = pixel_count * channel_count * bytes_per_channel;
  if (required_size > image->data_size) {
    return std::nullopt;
  }

  std::vector<uint8_t> bgra_bytes(pixel_count * 4u);
  size_t input_index = 0;
  size_t output_index = 0;

  for (size_t i = 0; i < pixel_count; ++i) {
    uint8_t red = 0;
    uint8_t green = 0;
    uint8_t blue = 0;
    if (image->bits == 8) {
      if (image->colors == 1) {
        red = green = blue = image->data[input_index];
        input_index += 1;
      } else {
        red = image->data[input_index];
        green = image->data[input_index + 1];
        blue = image->data[input_index + 2];
        input_index += 3;
      }
    } else {
      if (image->colors == 1) {
        red = green = blue = image->data[input_index + 1];
        input_index += 2;
      } else {
        red = image->data[input_index + 1];
        green = image->data[input_index + 3];
        blue = image->data[input_index + 5];
        input_index += 6;
      }
    }

    bgra_bytes[output_index++] = blue;
    bgra_bytes[output_index++] = green;
    bgra_bytes[output_index++] = red;
    bgra_bytes[output_index++] = 0xFF;
  }

  return EncodeBgraBitmapToPngBytes(bgra_bytes, image->width, image->height,
                                    max_edge);
}

std::optional<std::vector<uint8_t>> TryExtractLibRawPreview(
    LibRaw* processor, UINT max_edge) {
  if (processor == nullptr) {
    return std::nullopt;
  }

  const int unpack_result = processor->unpack_thumb();
  if (unpack_result != LIBRAW_SUCCESS) {
    return std::nullopt;
  }

  int error_code = LIBRAW_SUCCESS;
  libraw_processed_image_t* image =
      processor->dcraw_make_mem_thumb(&error_code);
  if (image == nullptr || error_code != LIBRAW_SUCCESS) {
    return std::nullopt;
  }

  std::optional<std::vector<uint8_t>> png_bytes;
  if (image->type == LIBRAW_IMAGE_JPEG || image->type == LIBRAW_IMAGE_JPEGXL ||
      image->type == LIBRAW_IMAGE_H265) {
    png_bytes = DecodeImageBufferToPngBytes(image->data, image->data_size,
                                            max_edge);
  } else if (image->type == LIBRAW_IMAGE_BITMAP) {
    png_bytes = EncodeLibRawProcessedImageToPngBytes(image, max_edge);
  }

  libraw_dcraw_clear_mem(image);
  return png_bytes;
}

std::optional<std::vector<uint8_t>> TryRenderLibRawImage(
    const std::wstring& path, UINT max_edge) {
  LibRaw processor;
  if (processor.open_file(path.c_str()) != LIBRAW_SUCCESS) {
    return std::nullopt;
  }

  processor.imgdata.params.half_size = 1;
  processor.imgdata.params.use_camera_wb = 1;
  processor.imgdata.params.use_auto_wb = 0;
  processor.imgdata.params.no_auto_bright = 1;
  processor.imgdata.params.output_bps = 8;
  processor.imgdata.params.output_color = 1;

  if (processor.unpack() != LIBRAW_SUCCESS) {
    return std::nullopt;
  }
  if (processor.dcraw_process() != LIBRAW_SUCCESS) {
    return std::nullopt;
  }

  int error_code = LIBRAW_SUCCESS;
  libraw_processed_image_t* image =
      processor.dcraw_make_mem_image(&error_code);
  if (image == nullptr || error_code != LIBRAW_SUCCESS) {
    return std::nullopt;
  }

  auto png_bytes = EncodeLibRawProcessedImageToPngBytes(image, max_edge);
  libraw_dcraw_clear_mem(image);
  return png_bytes;
}

std::optional<std::vector<uint8_t>> TryGenerateRawThumbnail(
    const std::wstring& path, UINT max_edge) {
  LibRaw preview_processor;
  if (preview_processor.open_file(path.c_str()) == LIBRAW_SUCCESS) {
    if (auto preview = TryExtractLibRawPreview(&preview_processor, max_edge)) {
      return preview;
    }
  }

  return TryRenderLibRawImage(path, max_edge);
}

std::optional<std::vector<uint8_t>> TryExtractPsdEmbeddedThumbnail(
    const std::wstring& path, UINT max_edge) {
  std::vector<uint8_t> bytes;
  if (!ReadSmallBinaryFile(path, kMaxPsdFileSizeBytes, &bytes)) {
    return std::nullopt;
  }

  if (bytes.size() < 30 || std::memcmp(bytes.data(), "8BPS", 4) != 0) {
    return std::nullopt;
  }

  size_t offset = 26;
  if (offset + 4 > bytes.size()) {
    return std::nullopt;
  }

  const uint32_t color_mode_length = ReadBigEndian32(&bytes[offset]);
  offset += 4;
  if (offset + color_mode_length > bytes.size()) {
    return std::nullopt;
  }
  offset += color_mode_length;

  if (offset + 4 > bytes.size()) {
    return std::nullopt;
  }

  const uint32_t image_resources_length = ReadBigEndian32(&bytes[offset]);
  offset += 4;
  if (offset + image_resources_length > bytes.size()) {
    return std::nullopt;
  }

  const size_t resource_end = offset + image_resources_length;
  while (offset + 12 <= resource_end) {
    if (std::memcmp(&bytes[offset], "8BIM", 4) != 0) {
      break;
    }
    offset += 4;

    const uint16_t resource_id = ReadBigEndian16(&bytes[offset]);
    offset += 2;

    const uint8_t name_length = bytes[offset];
    offset += 1;
    if (offset + name_length > resource_end) {
      return std::nullopt;
    }
    offset += name_length;
    if (((name_length + 1) & 1) != 0) {
      if (offset >= resource_end) {
        return std::nullopt;
      }
      offset += 1;
    }

    if (offset + 4 > resource_end) {
      return std::nullopt;
    }

    const uint32_t resource_size = ReadBigEndian32(&bytes[offset]);
    offset += 4;
    if (offset + resource_size > resource_end) {
      return std::nullopt;
    }

    if ((resource_id == 1036 || resource_id == 1033) &&
        resource_size > kPsdThumbnailHeaderSize) {
      const uint8_t* thumbnail_bytes =
          &bytes[offset + kPsdThumbnailHeaderSize];
      const size_t thumbnail_size = resource_size - kPsdThumbnailHeaderSize;
      if (thumbnail_size >= 2 && thumbnail_bytes[0] == 0xFF &&
          thumbnail_bytes[1] == 0xD8) {
        if (auto png =
                DecodeImageBufferToPngBytes(thumbnail_bytes, thumbnail_size,
                                            max_edge)) {
          return png;
        }
      }
    }

    offset += resource_size;
    if ((resource_size & 1u) != 0u) {
      if (offset >= resource_end) {
        return std::nullopt;
      }
      offset += 1;
    }
  }

  return std::nullopt;
}

std::optional<std::vector<uint8_t>> GenerateSpecialThumbnail(
    const std::wstring& path, std::string_view format_hint, UINT max_edge) {
  if (auto shell_thumbnail = TryGetShellThumbnail(path, max_edge)) {
    return shell_thumbnail;
  }

  if (format_hint == "raw") {
    return TryGenerateRawThumbnail(path, max_edge);
  }
  if (format_hint == "psd") {
    return TryExtractPsdEmbeddedThumbnail(path, max_edge);
  }
  return std::nullopt;
}

std::optional<std::string> GetStringArgument(
    const flutter::EncodableMap& arguments, const char* key) {
  const auto iterator = arguments.find(flutter::EncodableValue(key));
  if (iterator == arguments.end()) {
    return std::nullopt;
  }
  if (const auto* value = std::get_if<std::string>(&iterator->second)) {
    return *value;
  }
  return std::nullopt;
}

std::optional<int> GetIntArgument(const flutter::EncodableMap& arguments,
                                  const char* key) {
  const auto iterator = arguments.find(flutter::EncodableValue(key));
  if (iterator == arguments.end()) {
    return std::nullopt;
  }
  if (const auto* int_value = std::get_if<int32_t>(&iterator->second)) {
    return static_cast<int>(*int_value);
  }
  if (const auto* int_value = std::get_if<int64_t>(&iterator->second)) {
    return static_cast<int>(*int_value);
  }
  return std::nullopt;
}

}  // namespace

SpecialThumbnailChannel::SpecialThumbnailChannel(
    flutter::BinaryMessenger* messenger) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "path_extractor_browser/special_thumbnail",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](
                                     const auto& method_call,
                                     std::unique_ptr<flutter::MethodResult<
                                         flutter::EncodableValue>> result) {
    HandleMethodCall(method_call, std::move(result));
  });
}

SpecialThumbnailChannel::~SpecialThumbnailChannel() = default;

void SpecialThumbnailChannel::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name() != "generateSpecialThumbnail") {
    result->NotImplemented();
    return;
  }

  const auto* arguments =
      std::get_if<flutter::EncodableMap>(method_call.arguments());
  if (arguments == nullptr) {
    result->Success();
    return;
  }

  const auto path_value = GetStringArgument(*arguments, "path");
  const auto format_hint = GetStringArgument(*arguments, "formatHint");
  const auto max_edge_value = GetIntArgument(*arguments, "maxEdge");
  if (!path_value.has_value() || !format_hint.has_value() ||
      !max_edge_value.has_value()) {
    result->Success();
    return;
  }

  const std::wstring wide_path = Utf16FromUtf8(path_value->c_str());
  if (wide_path.empty()) {
    result->Success();
    return;
  }

  const int clamped_edge = std::clamp(*max_edge_value, 1, 4096);
  auto thumbnail_bytes = GenerateSpecialThumbnail(
      wide_path, *format_hint, static_cast<UINT>(clamped_edge));
  if (!thumbnail_bytes.has_value() || thumbnail_bytes->empty()) {
    result->Success();
    return;
  }

  result->Success(flutter::EncodableValue(*thumbnail_bytes));
}
