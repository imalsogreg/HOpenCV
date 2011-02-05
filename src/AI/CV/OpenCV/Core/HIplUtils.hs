{-# LANGUAGE ScopedTypeVariables, BangPatterns, MultiParamTypeClasses, 
             FlexibleInstances #-}
-- |Functions for working with 'HIplImage's.
module AI.CV.OpenCV.Core.HIplUtils 
    (isColor, isMono, imgChannels, withPixels, pixels,
     fromPtr, fromFileColor, fromFileGray, toFile, 
     compatibleImage, duplicateImage, fromPixels,
     withImagePixels, fromGrayPixels, fromColorPixels,
     withDuplicateImage, withCompatibleImage, pipeline,
     HIplImage, mkHIplImage, width, height, mkBlackImage,
     withHIplImage, MonoChromatic, TriChromatic, HasChannels, 
     HasDepth(..), HasScalar(..), IsCvScalar(..), colorDepth,
     ByteOrFloat, getROI) where
import AI.CV.OpenCV.Core.CxCore (IplImage)
import AI.CV.OpenCV.Core.HighGui (cvLoadImage, cvSaveImage, LoadColor(..))
import AI.CV.OpenCV.Core.HIplImage
import Control.Monad ((<=<))
import Control.Monad.ST (runST, unsafeIOToST)
import qualified Data.Vector.Storable as V
import Data.Word (Word8)
import Foreign.ForeignPtr
import Foreign.Marshal.Utils (copyBytes)
import Foreign.Ptr
import Foreign.Storable
import System.Directory (doesFileExist)
import System.IO.Unsafe
import Unsafe.Coerce

-- |This is a way to let the type checker know that you belieave an
-- image to be tri-chromatic.
isColor :: HIplImage TriChromatic d -> HIplImage TriChromatic d
isColor = id

-- |This is a way to let the type checker know that you believe an
-- image to be monochromatic.
isMono :: HIplImage MonoChromatic d -> HIplImage MonoChromatic d
isMono = id

{-# INLINE isMono #-}
{-# INLINE isColor #-}

-- |Return the number of color channels a 'HIplImage' has as a runtime
-- value.
imgChannels :: forall c d. HasChannels c => HIplImage c d -> Int
imgChannels _ = numChannels (undefined::c)

-- |Return the number of bytes per pixel color component of an
-- 'HIplImage'.
colorDepth :: forall c d. HasDepth d => HIplImage c d -> Int
colorDepth _ = bytesPerPixel (undefined::d)

-- |Apply the supplied function to a 'V.Vector' containing the pixels
-- that make up an 'HIplImage'. This does not copy the underlying
-- data.
withImagePixels :: HasDepth d => HIplImage c d -> (V.Vector d -> r) -> r
withImagePixels img f = f $ V.unsafeFromForeignPtr (imageData img) 0 n
    where n = imageSize img `div` colorDepth img

-- |Return a 'V.Vector' containing a copy of the pixels that make up a
-- 'HIplImage'.
pixels :: Storable d => HIplImage c d -> V.Vector d
pixels img = unsafePerformIO $ 
             do ptr <- mallocForeignPtrBytes len
                withForeignPtr ptr $ \dst -> 
                    withForeignPtr (imageData img) $ \src -> 
                        copyBytes dst src len
                return $ V.unsafeFromForeignPtr ptr 0 len
    where len = imageSize img

-- |Read a 'HIplImage' from a 'Ptr' 'IplImage'
fromPtr :: (HasChannels c, HasDepth d) => Ptr IplImage -> IO (HIplImage c d)
fromPtr = peek . castPtr

-- Ensure that a file exists.
checkFile :: FilePath -> IO ()
checkFile f = do e <- doesFileExist f
                 if e then return () else error $ "Can't find "++f

-- |Load a color 'HIplImage' from an 8-bit image file. If the image
-- file is grayscale, it will be converted to color.
fromFileColor :: FilePath -> IO (HIplImage TriChromatic Word8)
fromFileColor fileName = do checkFile fileName
                            ptr <- cvLoadImage fileName LoadColor
                            img <- fromPtr ptr :: IO (HIplImage TriChromatic Word8)
                            return $ unsafeCoerce img

-- |Load a grayscale 'HIplImage' from an 8-bit image file. If the
-- image file is color, it will be converted to grayscale.
fromFileGray :: FilePath -> IO (HIplImage MonoChromatic Word8)
fromFileGray fileName = do checkFile fileName
                           ptr <- cvLoadImage fileName LoadGray
                           img <- fromPtr ptr :: IO (HIplImage MonoChromatic Word8)
                           return $ unsafeCoerce img

-- |Save a 'HIplImage' to the specified file.
toFile :: (HasChannels c, HasDepth d) => FilePath -> HIplImage c d -> IO ()
toFile fileName img = withHIplImage img $ \ptr -> cvSaveImage fileName ptr


-- |Allocate a new 'HIplImage' with the same dimensions, number of
-- color channels, and color depth as an existing HIplImage. The pixel
-- data of the original 'HIplImage' is not copied.
compatibleImage :: HIplImage c d -> IO (HIplImage c d)
compatibleImage img@(HIplImage _ _ _ _ _ _) = 
    do ptr <- mallocForeignPtrArray sz
       return $ HIplImage 0 w h sz ptr stride
    where w = width img
          h = height img
          sz = imageSize img
          stride = widthStep img

-- |Create an exact duplicate of the given HIplImage. This allocates a
-- fresh array to store the copied pixels.
duplicateImage :: HIplImage c d -> IO (HIplImage c d)
duplicateImage img@(HIplImage _ _ _ _ _ _ ) =
    do fptr <- mallocForeignPtrArray sz
       withForeignPtr (imageData img) $ 
           \src -> withForeignPtr fptr $ \dst -> copyBytes dst src sz
       return $ HIplImage 0 w h sz fptr stride
    where w = width img
          h = height img
          sz = imageSize img
          stride = widthStep img

-- |Pass the given function a 'HIplImage' constructed from a width, a
-- height, and a 'V.Vector' of pixel values. The new 'HIplImage' \'s
-- pixel data is shared with the supplied 'V.Vector'.
withPixels :: forall a c d r. 
              (HasChannels c, Integral a, HasDepth d) =>
              a -> a -> V.Vector d -> (HIplImage c d -> r) -> r
withPixels w h pix f = if fromIntegral len == sz
                       then f $ HIplImage 0 w' h' sz fp (w'*nc)
                       else error "Length disagreement"
    where w' = fromIntegral w
          h' = fromIntegral h
          nc = numChannels (undefined::c)
          sz = w' * h' * nc
          (fp,len) = case V.unsafeToForeignPtr (V.force pix) of
                         (fp,0,len) -> (fp,len)
                         _ -> error "fromPixels non-zero offset"

-- |Construct a fresh 'HIplImage' from a width, a height, and a
-- 'V.Vector' of pixel values.
fromPixels :: forall a c d. 
              (Integral a, HasChannels c, HasDepth d) =>
              a -> a -> V.Vector d -> HIplImage c d
fromPixels w h pix = unsafePerformIO $ 
                     do fp <- copyData
                        return $ HIplImage 0 w' h' sz fp (w'*nc)
    where w' = fromIntegral w
          h' = fromIntegral h
          nc = numChannels (undefined::c)
          sz = w' * h' * nc
          copyData = let (vfp,offset,len) = V.unsafeToForeignPtr pix
                     in do fp <- mallocForeignPtrBytes len
                           withForeignPtr vfp $
                             \src -> withForeignPtr fp $
                                       \dst -> let src' = plusPtr src offset
                                               in copyBytes dst src' len
                           return fp
{-# INLINE [0] fromPixels #-}

-- |Helper function to explicitly type a vector of monochromatic pixel
-- data. Parameters are the output image's width, height, and pixel
-- content.
fromGrayPixels :: (HasDepth d, Integral a) => 
                  a -> a -> V.Vector d -> HIplImage MonoChromatic d
fromGrayPixels w h = isMono . fromPixels w h

-- |Helper function to explicitly type a vector of trichromatic pixel
-- data. Parameters are the output image's width, height, and pixel
-- content.
fromColorPixels :: (HasDepth d, Integral a) =>
                   a -> a -> V.Vector d -> HIplImage TriChromatic d
fromColorPixels w h = isColor . fromPixels w h

-- |Provides the supplied function with a 'Ptr' to the 'IplImage'
-- underlying a new 'HIplImage' that is an exact duplicate of the
-- given 'HIplImage'. Returns the duplicate 'HIplImage' after
-- performing the given action along with the result of that action.
withDuplicateImage :: (HasChannels c, HasDepth d) => 
                      HIplImage c d -> (Ptr IplImage -> IO b) -> 
                      (HIplImage c d, b)
withDuplicateImage img1 f = unsafePerformIO $
                            do img2 <- duplicateImage img1
                               r <- withHIplImage img2 f
                               return (img2, r)
{-# NOINLINE withDuplicateImage #-}

-- |Provides the supplied function with a 'Ptr' to the 'IplImage'
-- underlying a new 'HIplImage' of the same dimensions as the given
-- 'HIplImage'.
withCompatibleImage :: (HasChannels c, HasDepth d) => 
                       HIplImage c d -> (Ptr IplImage -> IO b) -> 
                       (HIplImage c d, b)
withCompatibleImage img1 f = runST $ unsafeIOToST $
                             do img2 <- compatibleImage img1
                                r <- withHIplImage img2 f
                                return (img2, r)
{-# NOINLINE withCompatibleImage #-}

-- |Extract a rectangular region of interest from an image. Returns a
-- new image whose pixel data is copied from the ROI of the source
-- image. Parameters are the upper-left corner of the ROI in image
-- coordinates, the (width,height) of the ROI in pixels, and the
-- source 'HIplImage'.
getROI :: (HasChannels c, HasDepth d) =>
          (Int,Int) -> (Int,Int) -> HIplImage c d -> HIplImage c d
getROI (rx,ry) (rw,rh) src = 
    unsafePerformIO $
    do img <- mkHIplImage rw rh
       withForeignPtr (imageData img) $ \dst ->
         withForeignPtr (imageData src) $ \src ->
           mapM_ (\(dOff, sOff) -> copyBytes (plusPtr dst dOff) 
                                             (plusPtr src sOff)
                                             rowLen)
                 (zip [0,rowLen..rw*rh*bpp-1] [start,start+stride..])
       return img
    where stride = fromIntegral $ widthStep src
          start = stride*ry + rx*bpp
          bpp = imgChannels src * colorDepth src
          rowLen = rw*bpp

pipeline :: (HIplImage c d -> IO r) -> HIplImage c d -> r
pipeline f = unsafePerformIO . (f <=< duplicateImage)
{-# INLINE [0] pipeline #-}

{-# RULES
"pipeline/join" forall f g h.
  pipeline f (pipeline g h) = pipeline (f <=< g) h
"pipeline/compose" forall f g.
  pipeline f . pipeline g = pipeline (f <=< g)
  #-}
