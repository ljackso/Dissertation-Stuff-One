
Used to run all the .gol test cases I have created
My Modules 

> import GoalCompiler
> import GoalParser

Other Modules

> import Data.List
> import Data.List.Split
> import System.Directory
> import System.IO.Unsafe




Used to run all test cases 

> runAllTests               = [runTest ("Tests\\GoalTestCases\\"++ n) | n <- findAllFiles]

> runTest fn                = if validFile fn then run fn else "" 

Finds all the file names for you

> findAllFiles              = unsafePerformIO (getDirectoryContents "Tests\\GoalTestCases\\") 


