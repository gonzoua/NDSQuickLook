#include <CoreFoundation/CoreFoundation.h>
#include <CoreServices/CoreServices.h>
#include <QuickLook/QuickLook.h>

#define ICON_WIDTH 32
#define ICON_HEIGHT 32
#define OFFSET_POSITION 0x068

struct banner_t
{
    uint16_t version;
    uint16_t crc16;
    unsigned char reserved[28];
    unsigned char tile_data[512];
    uint16_t palette[16];
    unsigned char jp_title[512];
    unsigned char en_title[512];
    unsigned char fr_title[512];
    unsigned char de_title[512];
    unsigned char it_title[512];
    unsigned char es_title[512];
} __attribute__((packed));

/*
 * Logo is always 32x32, color space is RGBA
 */
CGImageRef CreateImageFromLogo(uint8_t *pixels)
{
    CGColorSpaceRef colorspace;
    CGDataProviderRef data_provider;
    CGImageRef image;        
    
    colorspace = CGColorSpaceCreateDeviceRGB ();
    data_provider = CGDataProviderCreateWithData (NULL, pixels, 
                                                  ICON_WIDTH * ICON_HEIGHT * 4, NULL);
    
    image = CGImageCreate (ICON_WIDTH, ICON_HEIGHT, 8,
                           32, ICON_WIDTH*4,
                           colorspace,
                           kCGImageAlphaLast,
                           data_provider, NULL, FALSE,
                           kCGRenderingIntentDefault);
    
    CGDataProviderRelease (data_provider);
    CGColorSpaceRelease (colorspace);
    
    return image;
}

/* -----------------------------------------------------------------------------
    Generate a thumbnail for file

   This function's job is to create thumbnail for designated file as fast as possible
   ----------------------------------------------------------------------------- */

OSStatus GenerateThumbnailForURL(void *thisInterface, QLThumbnailRequestRef thumbnail, CFURLRef url, CFStringRef contentTypeUTI, CFDictionaryRef options, CGSize maxSize)
{
    CGContextRef ctx;
    CGSize sz;
    CGRect r;

    char cpath[PATH_MAX];
    CFStringRef cfpathref;
    int fd;
    off_t pos;
    uint32_t iconOffset;
    struct banner_t banner;    
    uint8_t pixels[ICON_WIDTH * ICON_HEIGHT * 4];
    
    cfpathref = CFURLCopyFileSystemPath(url, kCFURLPOSIXPathStyle);
    if( !cfpathref )
        return noErr;
    
    memset(cpath, 0, sizeof(cpath));
    
    if( CFStringGetCString(cfpathref, cpath, sizeof(cpath)-1, kCFStringEncodingUTF8) == FALSE) {
        CFRelease(cfpathref);
        return noErr;
    }
    
    CFRelease(cfpathref);

    fd = open(cpath, O_RDONLY);
    if (fd < 0)
        return noErr;
    
    pos = lseek(fd, OFFSET_POSITION, SEEK_SET);

    if (pos != OFFSET_POSITION) {
        close(fd);
        return noErr;
    }    
    
    if (read(fd, &iconOffset, 4) < 4) {
        close(fd);
        return noErr;
    }
    
    // TODO: big/little endian swap

    pos = lseek(fd, iconOffset, SEEK_SET);
    
    if (pos != iconOffset) {
        close(fd);
        return noErr;
    }
    
    if (read(fd, &banner, sizeof(banner)) < sizeof(banner)) {
        close(fd);
        return noErr;
    }
    
    close(fd);
    
    
    sz.height = ICON_WIDTH*8;
    sz.width = ICON_HEIGHT*8;
    ctx = QLThumbnailRequestCreateContext(thumbnail, sz, true, NULL);
    if( !ctx ) {
        return noErr;
    }

    r.origin.x = 0;
    r.origin.y = 0;
    r.size = sz;
    CGContextClearRect(ctx, r);
    
    CGContextSetShouldAntialias(ctx, true);
    CGContextSetShouldSmoothFonts(ctx, false);
    CGContextSetTextDrawingMode (ctx, kCGTextFillStroke);
    CGContextSetRGBFillColor (ctx, 0, 1, 0, 1);
    CGContextSetRGBStrokeColor (ctx, 0, 1, 0, 1);
    
    for (int tile = 0; tile < 16; tile++)
    {
        int tile_x = tile % 4;
        int tile_y = tile / 4;
        
        for (int x = 0; x < 8; x++) {
            for (int y = 0; y < 8; y++) {
                uint8_t color_idx = banner.tile_data[tile*32+(y*8+x)/2];
                if ((x % 2) == 1)
                    color_idx >>= 4;
                else
                    color_idx &= 0xf;
                // color = tile;
                uint16_t color = banner.palette[color_idx];
                // transparent color;
                if (color_idx == 0)
                    color = 0;
                CGFloat r, g, b;
                b = ((color >> 10) & 0x1f) / 31.;
                g = ((color >> 5) & 0x1f) / 31.;
                r = (color & 0x1f) / 31.;
                // r = g = b = tile/63.;
                int pixelOffset = ((tile_y * 8 + y) * ICON_WIDTH + (tile_x*8 + x)) * 4;
                pixels[pixelOffset + 0] = r*255;
                pixels[pixelOffset + 1] = g*255;
                pixels[pixelOffset + 2] = b*255;
                pixels[pixelOffset + 3] = 255;
            }
        }
    }
    
    CGImageRef imgRef = CreateImageFromLogo(pixels);
    CGContextDrawImage (ctx, CGRectMake(0, 0, sz.width, sz.height), imgRef);
    CGImageRelease(imgRef);
    
    QLThumbnailRequestFlushContext(thumbnail, ctx);
    return noErr;
}

void CancelThumbnailGeneration(void* thisInterface, QLThumbnailRequestRef thumbnail)
{
    // implement only if supported
}
