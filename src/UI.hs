module UI
  ( run
  ) where

import           Data.Word              (Word8)

import           Brick                  (App (..), AttrName, BrickEvent (..),
                                         EventM, Location (..), Next, Widget,
                                         attrMap, attrName, continue,
                                         defaultMain, emptyWidget, fg, halt,
                                         padAll, showCursor, showFirstCursor,
                                         str, withAttr, (<+>), (<=>))
import           Brick.Widgets.Center   (center)
import           Control.Monad.IO.Class (liftIO)
import           Data.Time              (getCurrentTime)
import           Graphics.Vty           (Attr, Color (..), Event (..), Key (..),
                                         Modifier (..), bold, defAttr,
                                         withStyle)

import           Data.Maybe             (fromMaybe)
import           GottaGoFast

emptyAttrName :: AttrName
emptyAttrName = attrName "empty"

errorAttrName :: AttrName
errorAttrName = attrName "error"

drawCharacter :: Character -> Widget ()
drawCharacter (Hit c)    = str [c]
drawCharacter (Miss ' ') = withAttr errorAttrName $ str ['_']
drawCharacter (Miss c)   = withAttr errorAttrName $ str [c]
drawCharacter (Empty c)  = withAttr emptyAttrName $ str [c]

drawLine :: Line -> Widget ()
-- We display an empty line as a single space so that it still occupies
-- vertical space.
drawLine [] = str " "
drawLine ls = foldl1 (<+>) $ map drawCharacter ls

drawPage :: State -> Widget ()
drawPage s = foldl (<=>) emptyWidget $ map drawLine $ page s

drawResults :: State -> Widget ()
drawResults s =
  str $
  "You typed " ++
  x ++
  " characters in " ++
  y ++
  " seconds.\n\n" ++
  "Words per minute: " ++
  show (round $ wpm s) ++
  "\n\n" ++ "Accuracy: " ++ show (round $ accuracy s * 100) ++ "%"
  where
    x = show $ noOfChars s
    y = show $ round $ seconds s

draw :: State -> [Widget ()]
draw s
  | hasEnded s = pure $ center $ drawResults s
  | otherwise = pure $ center p
  where
    p = padAll 1 $ showCursor () (Location $ cursor s) $ drawPage s

handleEnter :: State -> EventM () (Next State)
handleEnter s
  | not $ onLastLine s = continue $ applyEnter s
  | isComplete $ applyChar '\n' s = do
    now <- liftIO getCurrentTime
    continue $ stopClock now s
  | otherwise = continue s

handleChar :: Char -> State -> EventM () (Next State)
handleChar c s
  | c == ' ' && atEndOfLine s = handleEnter s
  | hasStarted s = continue $ applyChar c s
  | otherwise = do
    now <- liftIO getCurrentTime
    continue $ applyChar c $ startClock now s

handleEvent :: State -> BrickEvent () e -> EventM () (Next State)
handleEvent s (VtyEvent (EvKey key [MCtrl])) =
  case key of
    KChar 'c' -> halt s
    KChar 'd' -> halt s
    _         -> continue s
handleEvent s (VtyEvent (EvKey key []))
  | hasEnded s =
    case key of
      KEnter -> halt s
      KEsc   -> halt s
      _      -> continue s
  | otherwise =
    case key of
      KChar '\t' -> continue $ applyTab s
      KChar c    -> handleChar c s
      KEnter     -> handleEnter s
      KBS        -> continue $ applyBackspace s
      _          -> continue s
handleEvent s _ = continue s

app :: Attr -> Attr -> App State e ()
app emptyAttr errorAttr =
  App
    { appDraw = draw
    , appChooseCursor = showFirstCursor
    , appHandleEvent = handleEvent
    , appStartEvent = return
    , appAttrMap =
        const $
        attrMap defAttr [(emptyAttrName, emptyAttr), (errorAttrName, errorAttr)]
    }

run :: Maybe Word8 -> Maybe Word8 -> String -> IO ()
run fgEmptyCode fgErrorCode t = do
  _ <- defaultMain (app emptyAttr errorAttr) $ initialState t
  return ()
  where
    emptyAttr = fg $ maybe (Color240 231) ISOColor fgEmptyCode
    errorAttr = flip withStyle bold . fg . ISOColor $ fromMaybe 1 fgErrorCode
