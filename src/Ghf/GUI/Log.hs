--
-- | The log pane og ghf
--

module Ghf.GUI.Log (
    initLog
,   getLog
,   isLog
,   appendLog
,   LogTag(..)
) where

import Graphics.UI.Gtk hiding (afterToggleOverwrite)
import Graphics.UI.Gtk.SourceView
import Graphics.UI.Gtk.Multiline.TextView
import Control.Monad.Reader
import Data.IORef
import System.IO
import qualified Data.Map as Map
import Data.Map (Map,(!))

import Ghf.Core
--import Ghf.GUI.ViewFrame
import Ghf.GUI.SourceCandy

import Ghf.Core

logPaneName = "Log"

data LogTag = LogTag | ErrorTag | FrameTag

initLog :: PanePath -> Notebook -> GhfAction
initLog panePath nb = do
    ghfR <- ask
    panes <- readGhf panes
    paneMap <- readGhf paneMap
    prefs <- readGhf prefs
    (buf,cids) <- lift $ do
        tv <- textViewNew
        buf <- textViewGetBuffer tv
        iter <- textBufferGetEndIter buf
        textBufferCreateMark buf (Just "end") iter True
        tags <- textBufferGetTagTable buf
        errtag <- textTagNew (Just "err")
        set errtag[textTagForeground := "red"]
        textTagTableAdd tags errtag
        frametag <- textTagNew (Just "frame")
        set frametag[textTagForeground := "green"]
        textTagTableAdd tags frametag
        textViewSetEditable tv False
        fd <- case logviewFont prefs of
            Just str -> do
                fontDescriptionFromString str
            Nothing -> do
                f <- fontDescriptionNew
                fontDescriptionSetFamily f "Sans"
                return f
        widgetModifyFont tv (Just fd)
        sw <- scrolledWindowNew Nothing Nothing
        containerAdd sw tv
        scrolledWindowSetPolicy sw PolicyAutomatic PolicyAutomatic
        scrolledWindowSetShadowType sw ShadowIn

        let buf = GhfLog tv sw
        notebookPrependPage nb sw logPaneName
        widgetShowAll (scrolledWindowL buf)
        mbPn <- notebookPageNum nb sw
        case mbPn of
            Just i -> notebookSetCurrentPage nb i
            Nothing -> putStrLn "Notebook page not found"
        cid1 <- (castToWidget tv) `afterFocusIn`
            (\_ -> do runReaderT (makeLogActive buf) ghfR; return True)
        return (buf,[cid1])
    let newPaneMap  =  Map.insert (LogPane buf) (panePath,cids) paneMap
    let newPanes = Map.insert logPaneName (LogPane buf) panes
    modifyGhf_ (\ghf -> return (ghf{panes = newPanes,
                                    paneMap = newPaneMap}))
    lift $widgetGrabFocus (textView buf)

makeLogActive :: GhfLog -> GhfAction
makeLogActive log = do
    ghfR    <-  ask
    mbAP    <-  readGhf activePane
    case mbAP of
        Just (_,BufConnections signals signals2) -> lift $do
            mapM_ signalDisconnect signals
            mapM_ signalDisconnect signals2
        Nothing -> return ()
    modifyGhf_ $ \ghf -> do
        return (ghf{activePane = Just (LogPane log,BufConnections[] [])})

getLog :: GhfM GhfLog
getLog = do
    panesST <- readGhf panes
    let logs = map (\ (LogPane b) -> b) $filter isLog $Map.elems panesST
    if null logs || length logs > 1
        then error "no log buf or more then one log buf"
        else return (head logs)

isLog :: GhfPane -> Bool
isLog (LogPane _)    = True
isLog _             = False

appendLog :: GhfLog -> String -> LogTag -> IO ()
appendLog (GhfLog tv _) string tag = do
    buf <- textViewGetBuffer tv
    iter <- textBufferGetEndIter buf
    textBufferInsert buf iter string
    iter2 <- textBufferGetEndIter buf
    case tag of
        LogTag -> return ()
        ErrorTag -> do
            len <- textBufferGetCharCount buf
            strti <- textBufferGetIterAtOffset buf (len - length string)
            textBufferApplyTagByName buf "err" iter2 strti
        FrameTag -> do
            len <- textBufferGetCharCount buf
            strti <- textBufferGetIterAtOffset buf (len - length string)
            textBufferApplyTagByName buf "frame" iter2 strti
    textBufferMoveMarkByName buf "end" iter2
    mbMark <- textBufferGetMark buf "end"
    case mbMark of
        Nothing -> return ()
        Just mark -> textViewScrollMarkOnscreen tv mark
    return ()



