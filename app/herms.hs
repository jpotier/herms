module Main where

import System.Environment
import System.Directory
import System.IO
import Control.Monad
import Data.Char
import Data.Ratio
import Data.List
import Data.Maybe
import Control.Applicative
import Text.Read
import Utils
import AddCLI
import Types
import Paths_herms

-- Global constant
recipesFileName = "recipes.herms"

getRecipeBook :: IO [Recipe]
getRecipeBook = do
  fileName <- getDataFileName recipesFileName
  contents <- readFile fileName
  return $ map read $ lines contents

getRecipe :: String -> [Recipe] -> Maybe Recipe
getRecipe target = listToMaybe . filter ((target ==) . recipeName)

saveOrDiscard :: [[String]]   -- input for the new recipe
              -> Maybe Recipe -- maybe an original recipe prior to any editing
              -> IO ()
saveOrDiscard input oldRecp = do
  let newRecipe = readRecipe input
  putStrLn $ showRecipe newRecipe Nothing
  putStrLn "Save recipe? (Y)es  (N)o  (E)dit"
  response <- getLine
  if response == "y" || response == "Y" 
    then do 
    recipeBook <- getRecipeBook
    let recpName = recipeName (fromJust oldRecp)
    unless (isNothing (readRecipeRef recpName recipeBook)) $ removeSilent [recpName]
    fileName <- getDataFileName recipesFileName
    appendFile fileName (show newRecipe ++ "\n")
    putStrLn "Recipe saved!"
  else if response == "n" || response == "N"
    then do
    putStrLn "Recipe discarded."
  else if response == "e" || response == "E"
    then do
    doEdit newRecipe oldRecp
  else
    do
    putStrLn "\nPlease enter ONLY 'y', 'n' or 'e'\n"
    saveOrDiscard input oldRecp

add :: [String] -> IO ()
add _ = do
  input <- getAddInput 
  saveOrDiscard input Nothing

doEdit :: Recipe -> Maybe Recipe -> IO ()
doEdit recp origRecp = do
  input <- getEdit (recipeName recp) (description recp) amounts units ingrs attrs dirs tag
  saveOrDiscard input origRecp
  where ingrList = ingredients recp
        toStr    = (\ f -> unlines (map f ingrList))
        amounts  = toStr (showFrac . quantity)
        units    = toStr unit
        ingrs    = toStr ingredientName
        dirs     = unlines (directions recp)
        attrs    = toStr attribute
        tag      = unlines (tags recp)
 
edit :: [String] -> IO ()
edit targets = do
  recipeBook <- getRecipeBook
  case readRecipeRef target recipeBook of
    Nothing   -> putStrLn $ target ++ " does not exist\n"
    Just recp -> doEdit recp (Just recp)
  where target = head targets -- Only supports editing one recipe per command

-- | `readRecipeRef target book` interprets the string `target`
--   as either an index or a recipe's name and looks up the
--   corresponding recipe in the `book`
readRecipeRef :: String -> [Recipe] -> Maybe Recipe
readRecipeRef target recipeBook =
  (safeLookup recipeBook . pred =<< readMaybe target)
  <|> getRecipe target recipeBook

sepFlags :: [String] -> [String]
sepFlags args = takeWhile (\x -> head x == '-') (sort args)

view :: [String] -> IO ()
view args = do
  recipeBook <- getRecipeBook
  let flags   = sepFlags args
  let cFlags  = concat flags
  let targets = args \\ flags
  let servings = case elemIndex 's' cFlags of
                   Nothing -> Nothing
                   Just i  -> Just (digitToInt (cFlags !! 2))
  forM_ targets $ \ target ->
    putStr $ case readRecipeRef target recipeBook of
      Nothing   -> target ++ " does not exist\n"
      Just recp -> showRecipe recp servings

list :: [String] -> IO ()
list _  = do
  recipes <- getRecipeBook
  let recipeList = map showRecipeInfo recipes
      size       = length $ show $ length recipeList
      indices    = map (padLeft size . show) [1..]
  putStr $ unlines $ zipWith (\ i -> ((i ++ ". ") ++)) indices recipeList


showRecipeInfo :: Recipe -> String
showRecipeInfo recipe = name ++ "\n\t" ++ desc  ++ "\n\t[Tags: " ++ showTags ++ "]"
  where name     = recipeName recipe
        desc     = (takeFullWords . description) recipe
        showTags = (intercalate ", " . tags) recipe

takeFullWords :: String -> String
takeFullWords = (unwords . takeFullWords' 0 . words)
  where takeFullWords' n (x:[]) | (length x + n) > 40 = []
                                | otherwise           = [x]
        takeFullWords' n (x:xs) | (length x + n) > 40 = [x ++ "..."]
                                | otherwise           =
                                  [x] ++ takeFullWords' ((length x) + n) xs

-- | @replaceDataFile fp str@ replaces the target data file @fp@ with
--   the new content @str@ in a safe manner: it opens a temporary file
--   first, writes to it, closes the handle, removes the target,
--   and finally moves the temporary file over to the target @fp@.

replaceDataFile :: FilePath -> String -> IO ()
replaceDataFile fp str = do
  (tempName, tempHandle) <- openTempFile "." "herms_temp"
  hPutStr tempHandle str
  hClose tempHandle
  fileName <- getDataFileName fp
  removeFile fileName
  renameFile tempName fileName

-- | @removeWithVerbosity v recipes@ deletes the @recipes@ from the
--   book, listing its work only if @v@ is set to @True@.
--   This subsumes both @remove@ and @removeSilent@.

removeWithVerbosity :: Bool -> [String] -> IO ()
removeWithVerbosity v targets = do
  recipeBook <- getRecipeBook
  mrecipes   <- forM targets $ \ target -> do
    -- Resolve the recipes all at once; this way if we remove multiple
    -- recipes based on their respective index, all of the index are
    -- resolved based on the state the book was in before we started to
    -- remove anything
    let mrecp = readRecipeRef target recipeBook
    () <- putStr $ case mrecp of
       Nothing -> target ++ " does not exist.\n"
       Just r  -> guard v *> "Removing recipe: " ++ recipeName r ++ "...\n"
    return mrecp
  -- Remove all the resolved recipes at once
  let newRecipeBook = recipeBook \\ catMaybes mrecipes
  replaceDataFile recipesFileName $ unlines $ show <$> newRecipeBook

remove :: [String] -> IO ()
remove = removeWithVerbosity True

removeSilent :: [String] -> IO ()
removeSilent = removeWithVerbosity False

help :: [String] -> IO ()
help _ = putStr $ unlines $ "Usage:" : usage where

  usage = map (\ (c, d) -> concat [ padRight size c, "   ", d ]) desc
  size  = maximum $ map (length . fst) desc
  desc  = [ ("\therms list", "list recipes")
          , ("","")
          , ("\therms view {index or \"Recipe Name\"}", "view a particular recipe")
          , ("","")
          , ("\therms add", "add a new recipe (interactive)")
          , ("","")
          , ("\therms edit {index or \"Recipe Name\"}", "edit a recipe")
          , ("","")
          , ("\therms remove {index or \"Recipe Name\"}", "remove a particular recipe")
          , ("","")
          , ("\therms help", "display this help")
          , ("","")
          , ("OPTIONS","")
          , ("\t-s{num}", "specify serving size when viewing.")
          , ("\t","E.g., 'herms view -s2 {recipe}' for two servings")
          ]

dispatch :: [(String, [String] -> IO ())]
dispatch = [ ("add", add)
           , ("view", view)
           , ("remove", remove)
           , ("list", list)
           , ("help", help)
           , ("edit", edit)
           ]

-- Writes an empty recipes file if it doesn't exist
checkFileExists :: IO ()
checkFileExists = do
  fileName <- getDataFileName recipesFileName
  fileExists <- doesFileExist fileName
  unless fileExists (do
    dirName <- getDataDir
    createDirectoryIfMissing True dirName
    writeFile fileName "")

herms :: [String]      -- command line arguments
      -> Maybe (IO ()) -- failure or resulting IO action
herms args = do
  guard (not $ null args)
  action <- lookup (head args) dispatch
  return $ action (tail args)

main :: IO ()
main = do
  checkFileExists
  testCmd <- getArgs
  fromMaybe (help [""]) (herms testCmd)
