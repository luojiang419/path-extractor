#ifndef RUNNER_SPECIAL_THUMBNAIL_CHANNEL_H_
#define RUNNER_SPECIAL_THUMBNAIL_CHANNEL_H_

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>

class SpecialThumbnailChannel {
 public:
  explicit SpecialThumbnailChannel(flutter::BinaryMessenger* messenger);
  ~SpecialThumbnailChannel();

  SpecialThumbnailChannel(const SpecialThumbnailChannel&) = delete;
  SpecialThumbnailChannel& operator=(const SpecialThumbnailChannel&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_SPECIAL_THUMBNAIL_CHANNEL_H_
