-- |Interfaces for grabbing images from cameras and video files, and
-- for writing to video files.
module AI.CV.OpenCV.Video (createFileCapture, createFileCaptureLoop, 
                           createCameraCapture, createVideoWriter, 
                           FourCC, mpeg4CC) where
import Foreign.Ptr
import Foreign.ForeignPtr (withForeignPtr)
import AI.CV.OpenCV.Core.CxCore
import AI.CV.OpenCV.Core.HIplUtil
import AI.CV.OpenCV.Core.HighGui

-- |Raise an error if 'cvQueryFrame' returns 'Nothing'; otherwise
-- returns a 'Ptr' 'IplImage'.
queryError :: Ptr CvCapture -> IO (Ptr IplImage)
queryError = (maybe (error "Unable to capture frame") id `fmap`) . cvQueryFrame

-- |If 'cvQueryFrame' returns 'Nothing', try rewinding the video and
-- querying again. If it still fails, raise an error. When a non-null
-- frame is obtained, return it.
queryFrameLoop :: Ptr CvCapture -> IO (Ptr IplImage)
queryFrameLoop cap = do f <- cvQueryFrame cap
                        case f of
                          Nothing -> do setCapturePos cap (PosFrames 0)
                                        queryError cap
                          Just f' -> return f'

-- |Open a capture stream from a movie file. The returned action may
-- be used to query for the next available frame. If no frame is
-- available either due to error or the end of the video sequence,
-- 'Nothing' is returned.
createFileCapture :: (HasChannels c, HasDepth d) => 
                     FilePath -> IO (IO (Maybe (HIplImage c d)))
createFileCapture fname = do capture <- createFileCaptureF fname
                             return (withForeignPtr capture $ \cap ->
                                       do f <- cvQueryFrame cap
                                          case f of
                                            Nothing -> return Nothing
                                            Just f' -> Just `fmap` fromPtr f')

-- |Open a capture stream from a movie file. The returned action may
-- be used to query for the next available frame. The sequence of
-- frames will return to its beginning when the end of the video is
-- encountered.
createFileCaptureLoop :: (HasChannels c, HasDepth d) =>
                         FilePath -> IO (IO (HIplImage c d))
createFileCaptureLoop fname = do capture <- createFileCaptureF fname
                                 return (withForeignPtr capture $ 
                                         (>>= fromPtr) . queryFrameLoop)


-- |Open a capture stream from a connected camera. The parameter is
-- the index of the camera to be used, or 'Nothing' if it does not
-- matter what camera is used. The returned action may be used to
-- query for the next available frame.
createCameraCapture :: (HasChannels c, HasDepth d) =>
                       Maybe Int -> IO (IO (HIplImage c d))
createCameraCapture cam = do cvInit
                             capture <- createCameraCaptureF cam'
                             return (withForeignPtr capture $ 
                                     (>>= fromPtr) . queryError)
    where cam' = maybe (-1) id cam

-- |4-character code for MPEG-4.
mpeg4CC :: FourCC
mpeg4CC = ('F','M','P','4')

-- |Create a video file writer. The parameters are the file name, the
-- 4-character code (of the codec used to compress the frames
-- (e.g. @(\'F\',\'M\',\'P\',\'4\')@ for MPEG-4), the framerate of the
-- created video stream, and the size of the video frames. The
-- returned action may be used to add frames to the video stream.
createVideoWriter :: (HasChannels c, HasDepth d) =>
                     FilePath -> FourCC -> Double -> (Int,Int) -> 
                     IO (HIplImage c d -> IO ())
createVideoWriter fname codec fps sz = 
    do writer <- createVideoWriterF fname codec fps sz
       let writeFrame img = withForeignPtr writer $ \writer' ->
                              withHIplImage img $ \img' ->
                                cvWriteFrame writer' img'
       return writeFrame