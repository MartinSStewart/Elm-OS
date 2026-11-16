module TicTacToeTest exposing (suite)

import Expect
import Test exposing (Test, describe, test)
import TicTacToe exposing (Mark(..), Status(..))


{-| Places marks on the squares in order, starting with X.
-}
play : List Int -> TicTacToe.Model
play squares =
    List.foldl TicTacToe.press TicTacToe.init squares


suite : Test
suite =
    describe "TicTacToe"
        [ test "X starts" (\_ -> TicTacToe.init.next |> Expect.equal X)
        , test "marks alternate"
            (\_ ->
                (play [ 0, 4 ]).squares
                    |> Expect.equal [ Just X, Nothing, Nothing, Nothing, Just O, Nothing, Nothing, Nothing, Nothing ]
            )
        , test "a square can't be taken twice"
            (\_ -> Expect.equal (play [ 0, 0 ]) (play [ 0 ]))
        , test "a square off the board is ignored"
            (\_ -> Expect.equal (play [ 9 ]) TicTacToe.init)
        , test "three in a row wins"
            (\_ -> Expect.equal (TicTacToe.status (play [ 0, 3, 1, 4, 2 ])) (Won X [ 0, 1, 2 ]))
        , test "a diagonal wins"
            (\_ -> Expect.equal (TicTacToe.status (play [ 2, 0, 4, 1, 6 ])) (Won X [ 2, 4, 6 ]))
        , test "O can win"
            (\_ -> Expect.equal (TicTacToe.status (play [ 0, 3, 1, 4, 8, 5 ])) (Won O [ 3, 4, 5 ]))
        , test "a full board with no line is a draw"
            -- X O X / X O O / O X X
            (\_ -> Expect.equal (TicTacToe.status (play [ 0, 1, 2, 4, 3, 5, 7, 6, 8 ])) Draw)
        , test "nothing changes after a win"
            (\_ -> Expect.equal (play [ 0, 3, 1, 4, 2, 5, 8 ]) (play [ 0, 3, 1, 4, 2 ]))
        , test "an unfinished game is still playing"
            (\_ -> Expect.equal (TicTacToe.status (play [ 0, 4 ])) Playing)
        ]
