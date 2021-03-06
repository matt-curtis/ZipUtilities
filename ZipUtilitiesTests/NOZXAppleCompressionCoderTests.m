//
//  NOZXAppleCompressionCoderTests.m
//  ZipUtilities
//
//  Created by Nolan O'Brien on 9/11/15.
//  Copyright © 2015 NSProgrammer. All rights reserved.
//

#import "NOZXAppleCompressionCoder.h"

@import XCTest;
@import ZipUtilities;

#if COMPRESSION_LIB_AVAILABLE

@interface NOZXAppleCompressionCoderTests : XCTestCase
@end

@implementation NOZXAppleCompressionCoderTests

+ (void)setUp
{
    if ([NOZXAppleCompressionCoder isSupported]) {

        // LZMA

        NOZUpdateCompressionMethodEncoder(NOZCompressionMethodLZMA, [NOZXAppleCompressionCoder encoderWithAlgorithm:COMPRESSION_LZMA]);
        NOZUpdateCompressionMethodDecoder(NOZCompressionMethodLZMA, [NOZXAppleCompressionCoder decoderWithAlgorithm:COMPRESSION_LZMA]);

        // LZ4

        NOZUpdateCompressionMethodEncoder((NOZCompressionMethod)COMPRESSION_LZ4, [NOZXAppleCompressionCoder encoderWithAlgorithm:COMPRESSION_LZ4]);
        NOZUpdateCompressionMethodDecoder((NOZCompressionMethod)COMPRESSION_LZ4, [NOZXAppleCompressionCoder decoderWithAlgorithm:COMPRESSION_LZ4]);

        // Apple LZFSE

        NOZUpdateCompressionMethodEncoder((NOZCompressionMethod)COMPRESSION_LZFSE, [NOZXAppleCompressionCoder encoderWithAlgorithm:COMPRESSION_LZFSE]);
        NOZUpdateCompressionMethodDecoder((NOZCompressionMethod)COMPRESSION_LZFSE, [NOZXAppleCompressionCoder decoderWithAlgorithm:COMPRESSION_LZFSE]);

    }
}

+ (void)tearDown
{
    if ([NOZXAppleCompressionCoder isSupported]) {

        // LZMA

        NOZUpdateCompressionMethodEncoder(NOZCompressionMethodLZMA, nil);
        NOZUpdateCompressionMethodDecoder(NOZCompressionMethodLZMA, nil);

        // LZ4

        NOZUpdateCompressionMethodEncoder((NOZCompressionMethod)COMPRESSION_LZ4, nil);
        NOZUpdateCompressionMethodDecoder((NOZCompressionMethod)COMPRESSION_LZ4, nil);

        // Apple LZFSE

        NOZUpdateCompressionMethodEncoder((NOZCompressionMethod)COMPRESSION_LZFSE, nil);
        NOZUpdateCompressionMethodDecoder((NOZCompressionMethod)COMPRESSION_LZFSE, nil);

    }
}

+ (BOOL)canTestWithMethod:(NOZCompressionMethod)method
{
    id<NOZEncoder> checkEncoder = NOZEncoderForCompressionMethod(method);
    id<NOZDecoder> checkDecoder = NOZDecoderForCompressionMethod(method);

    if (!checkEncoder || !checkDecoder) {
        return NO;
    }

    if (![NOZXAppleCompressionCoder isSupported]) {
        if ([checkEncoder isKindOfClass:[NOZXAppleCompressionCoder class]] ||
            [checkDecoder isKindOfClass:[NOZXAppleCompressionCoder class]]) {
            return NO;
        }
    }

    return YES;
}

- (void)runCodingWithMethod:(NOZCompressionMethod)method
{
    if (![[self class] canTestWithMethod:method]) {
        return;
    }

    NSString *zipDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
    [[NSFileManager defaultManager] createDirectoryAtPath:zipDirectory withIntermediateDirectories:YES attributes:NULL error:NULL];
    NSString *sourceFile = [[NSBundle bundleForClass:[self class]] pathForResource:@"Aesop" ofType:@"txt"];
    NSData *sourceData = [NSData dataWithContentsOfFile:sourceFile];
    __block NSData *unzippedData = nil;

    // Zip

    NOZFileZipEntry *entry = [[NOZFileZipEntry alloc] initWithFilePath:sourceFile];
    entry.compressionMethod = method;
    NSString *zipFileName = [NSString stringWithFormat:@"Aesop.%u.zip", method];
    NOZZipper *zipper = [[NOZZipper alloc] initWithZipFile:[zipDirectory stringByAppendingPathComponent:zipFileName]];
    XCTAssertTrue([zipper openWithMode:NOZZipperModeCreate error:NULL]);
    XCTAssertTrue([zipper addEntry:entry progressBlock:NULL error:NULL]);
    XCTAssertTrue([zipper closeAndReturnError:NULL]);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:zipper.zipFilePath]);

    // Unzip

    NOZUnzipper *unzipper = [[NOZUnzipper alloc] initWithZipFile:zipper.zipFilePath];
    XCTAssertTrue([unzipper openAndReturnError:NULL]);
    XCTAssertTrue([unzipper readCentralDirectoryAndReturnError:NULL]);
    [unzipper enumerateManifestEntriesUsingBlock:^(NOZCentralDirectoryRecord *record, NSUInteger index, BOOL *stop) {
        XCTAssertTrue([unzipper saveRecord:record toDirectory:zipDirectory options:NOZUnzipperSaveRecordOptionOverwriteExisting progressBlock:NULL error:NULL]);
        NSString *unzippedFilePath = [zipDirectory stringByAppendingPathComponent:record.name];
        XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:unzippedFilePath]);
        if ([record.name isEqualToString:sourceFile.lastPathComponent]) {
            unzippedData = [NSData dataWithContentsOfFile:unzippedFilePath];
        }
    }];
    XCTAssertTrue([unzipper closeAndReturnError:NULL]);
    XCTAssertEqualObjects(unzippedData, sourceData);

    // Cleanup

    [[NSFileManager defaultManager] removeItemAtPath:zipDirectory error:NULL];
}

- (void)runCategoryCodingTest:(NOZCompressionMethod)method
{
    if (![[self class] canTestWithMethod:method]) {
        return;
    }

    NSString *sourceFile = [[NSBundle bundleForClass:[self class]] pathForResource:@"Aesop" ofType:@"txt"];
    NSData *sourceData = [NSData dataWithContentsOfFile:sourceFile];

    NSData *compressedData;
    NSData *decompressedData;
    id<NOZEncoder> encoder = NOZEncoderForCompressionMethod(method);
    id<NOZDecoder> decoder = NOZDecoderForCompressionMethod(method);
    BOOL isRaw = NOZCompressionMethodNone == method;

    for (NSUInteger i = 0; i < 2; i++) {
        if (i == 0) {
            compressedData = [sourceData noz_dataByCompressing:encoder
                                              compressionLevel:NOZCompressionLevelMax];
        } else {
            NSInputStream *sourceStream = (i == 1) ? [NSInputStream inputStreamWithFileAtPath:sourceFile] : [NSInputStream inputStreamWithData:sourceData];
            sourceStream = [NSInputStream noz_compressedInputStream:sourceStream withEncoder:encoder compressionLevel:NOZCompressionLevelMax];

            const size_t bufferSize = NSPageSize();
            Byte buffer[bufferSize];
            NSMutableData *compressedDataM = [NSMutableData data];

            [sourceStream open];
            NSInteger bytesRead = 1;
            while (sourceStream.hasBytesAvailable && bytesRead > 0) {
                bytesRead = [sourceStream read:buffer maxLength:bufferSize];
                if (bytesRead > 0) {
                    [compressedDataM appendBytes:buffer length:(NSUInteger)bytesRead];
                }
            }
            [sourceStream close];

            XCTAssertFalse(sourceStream.hasBytesAvailable);
            XCTAssertGreaterThan(compressedDataM.length, (NSUInteger)0);
            compressedData = (!sourceStream.hasBytesAvailable && compressedDataM.length > 0) ? [compressedDataM copy] : nil;
        }

        if (encoder) {
            XCTAssertNotNil(compressedData);
            if (!isRaw) {
                XCTAssertLessThan(compressedData.length, sourceData.length);
                XCTAssertNotEqualObjects(compressedData, sourceData);
            } else {
                XCTAssertEqual(compressedData.length, sourceData.length);
                XCTAssertEqualObjects(compressedData, sourceData);
            }

            decompressedData = [compressedData noz_dataByDecompressing:decoder];

            if (decoder) {
                XCTAssertNotNil(decompressedData);
                XCTAssertEqual(decompressedData.length, sourceData.length);
                XCTAssertEqualObjects(decompressedData, sourceData);
            } else {
                XCTAssertNil(decompressedData);
            }
        } else {
            XCTAssertNil(compressedData);
        }
    }
}

- (void)testDeflate
{

    id<NOZEncoder> originalEncoder = NOZEncoderForCompressionMethod(NOZCompressionMethodDeflate);
    id<NOZDecoder> originalDecoder = NOZDecoderForCompressionMethod(NOZCompressionMethodDeflate);

    // Both custom

    NOZUpdateCompressionMethodEncoder(NOZCompressionMethodDeflate, [NOZXAppleCompressionCoder encoderWithAlgorithm:COMPRESSION_ZLIB]);
    NOZUpdateCompressionMethodDecoder(NOZCompressionMethodDeflate, [NOZXAppleCompressionCoder decoderWithAlgorithm:COMPRESSION_ZLIB]);

    [self runCodingWithMethod:NOZCompressionMethodDeflate];
    [self runCategoryCodingTest:NOZCompressionMethodDeflate];

    NOZUpdateCompressionMethodEncoder(NOZCompressionMethodDeflate, originalEncoder);
    NOZUpdateCompressionMethodDecoder(NOZCompressionMethodDeflate, originalDecoder);

    // Both original

    [self runCodingWithMethod:NOZCompressionMethodDeflate];
    [self runCategoryCodingTest:NOZCompressionMethodDeflate];

    // Original Encoder / Custom Decoder

    NOZUpdateCompressionMethodDecoder(NOZCompressionMethodDeflate, [NOZXAppleCompressionCoder decoderWithAlgorithm:COMPRESSION_ZLIB]);

    [self runCodingWithMethod:NOZCompressionMethodDeflate];
    [self runCategoryCodingTest:NOZCompressionMethodDeflate];

    NOZUpdateCompressionMethodDecoder(NOZCompressionMethodDeflate, originalDecoder);

    // Custom Encoder / Original Decoder

    NOZUpdateCompressionMethodEncoder(NOZCompressionMethodDeflate, [NOZXAppleCompressionCoder encoderWithAlgorithm:COMPRESSION_ZLIB]);

    [self runCodingWithMethod:NOZCompressionMethodDeflate];
    [self runCategoryCodingTest:NOZCompressionMethodDeflate];

    NOZUpdateCompressionMethodEncoder(NOZCompressionMethodDeflate, originalEncoder);

}

- (void)testLZMACoding
{
    [self runCodingWithMethod:NOZCompressionMethodLZMA];
    [self runCategoryCodingTest:NOZCompressionMethodLZMA];
}

- (void)testLZ4Coding
{
    [self runCodingWithMethod:(NOZCompressionMethod)COMPRESSION_LZ4];
    [self runCategoryCodingTest:(NOZCompressionMethod)COMPRESSION_LZ4];
}

- (void)testLZFSECoding
{
    [self runCodingWithMethod:(NOZCompressionMethod)COMPRESSION_LZFSE];
    [self runCategoryCodingTest:(NOZCompressionMethod)COMPRESSION_LZFSE];
}

- (void)testRawCoding
{
    [self runCodingWithMethod:NOZCompressionMethodNone];
    [self runCategoryCodingTest:NOZCompressionMethodNone];
}

@end

#endif
