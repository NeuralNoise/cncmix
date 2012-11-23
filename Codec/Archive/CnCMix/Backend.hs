module Codec.Archive.CnCMix.Backend where
--       (
--         File
--       , name
--       , contents
--         --, Mix
--       ) where

import Data.Word
import Data.Int
import Data.Bits
import Data.Char
import Data.List
import Data.Maybe

import Numeric

import System.FilePath
import qualified Data.ByteString.Lazy as L

import Data.Binary
import Data.Binary.Get
import Data.Binary.Put

import qualified Control.Monad as S
--import qualified Control.Monad.Parallel as P

data File3 = File3 { name     :: String
                   , id       :: Word32
                   , contents :: L.ByteString }
           deriving (Show, Read, Eq)


--
-- Porcelain File Operators
--

readFile3 :: (File3 -> File3) -> FilePath -> IO File3
readFile3 f p = return . f . File3 shortname 0 =<< L.readFile p
  where shortname = takeFileName p

readFile3s :: (File3 -> File3) -> [FilePath] -> IO [File3]
readFile3s f = S.mapM $ readFile3 f

writeFile3 :: FilePath -> File3 -> IO ()
writeFile3 p (File3 n _ c) = L.writeFile (p </> n) $ c

writeFile3s :: FilePath -> [File3] -> IO ()
writeFile3s = S.mapM_ . writeFile3

removeFile3s :: File3 -> [File3] -> [File3]
removeFile3s new@(File3 nn ni _) fs = filter (detectFile3 nn ni) fs

mergeFile3s ::[File3] -> [File3] -> [File3]
mergeFile3s = combineFile3sGeneric combineDestructiveFile3 True

mergeFile3 :: File3 -> [File3] -> [File3]
mergeFile3 a = mergeFile3s [a]

detectFile3 :: String -> Word32 -> File3 -> Bool
detectFile3 n i x = (i == Codec.Archive.CnCMix.Backend.id x)
                    || (n == name x)

updateMetadataFile3s = combineFile3sGeneric combineSafeFile3 False

--
-- Plumbing File Operators
--

combineDestructiveFile3 :: File3 -> File3 -> Maybe File3
combineDestructiveFile3 (File3 n1 i1 c1) (File3 n2 i2 c2) =
  case results of
    (Just a, Just b) -> Just $ File3 a b c1
    (_, _)           -> Nothing
  where results = (cF n1 n2 [], cF i1 i2 0)
        cF a b base
          | a == base = Just b
          | b == base = Just a
          | a == b    = Just a
          | otherwise = Just a

combineSafeFile3 :: File3 -> File3 -> Maybe File3
combineSafeFile3 (File3 n1 i1 c1) (File3 n2 i2 c2) =
  case results of
    (Just a, Just b, Just c) -> Just $ File3 a b c
    (_, _, _)                -> Nothing
  where results = (cF n1 n2 [], cF i1 i2 0, cF c1 c2 L.empty)
        cF a b base
          | a == base = Just b
          | b == base = Just a
          | a == b    = Just a
          | otherwise = Nothing

combineFile3sGeneric :: (File3 -> File3 -> Maybe File3)
                        -> Bool -> [File3] -> [File3] -> [File3]
combineFile3sGeneric _ True  k  [] = k
combineFile3sGeneric _ False _  [] = []
combineFile3sGeneric _ _     [] k  = k
combineFile3sGeneric f b meta real = case partition (isJust . f' hR) meta of
  (x@(_:_), y) -> (foldl (\a -> g . f' a) hR x) : combineFile3sGeneric f b y tR
  ([], (_:_))  -> hR : combineFile3sGeneric f b meta tR
  where f' = flip f;    g = \(Just a) -> a
        hM = head meta; tM = tail meta
        hR = head real; tR = tail real


--
-- Archive Type Class
--

class (Binary a) => Archive a where
  -- | Creates a TAR archive containing a number of files
  filesToArchive :: [File3] -> a
  archiveToFiles :: a -> [File3]


  cons :: File3 -> a -> a
  cons f = filesToArchive . (f :) . archiveToFiles


showFileNames :: [File3] -> [String]
showFileNames = map (name :: File3 -> String)