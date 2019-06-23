module Routes exposing (Route(..), browseTopic, getPath, getTopicOverViewPath, getViewTopicPath, parseUrl, routeParser, sendMessageRoute)

import Dict
import Topic exposing (PartitionOffsets)
import Url exposing (Url)
import Url.Parser as Parser exposing ((</>), (<?>), Parser, oneOf, s)
import Url.Parser.Query as Q


type Route
    = RootRoute
    | TopicsRoute
    | SendMessageRoute String Int
    | ViewTopicRoute String PartitionOffsets
    | NotFound


routeParser : Parser (Route -> a) a
routeParser =
    oneOf
        [ Parser.map RootRoute Parser.top
        , Parser.map ViewTopicRoute (s "topic" </> Parser.string <?> partitionOffsetUrlParser)
        , Parser.map SendMessageRoute (s "topic" </> Parser.string </> s "sendMessage" </> Parser.int)
        , Parser.map TopicsRoute (s "topics")
        ]


parseUrl : Url -> Route
parseUrl url =
    case Parser.parse routeParser url of
        Just route ->
            route

        Nothing ->
            NotFound


getPath : Route -> String
getPath route =
    case route of
        NotFound ->
            "/404"

        TopicsRoute ->
            "/topics"

        SendMessageRoute topicName partition ->
            "/topic/" ++ topicName ++ "/sendMessage/" ++ String.fromInt partition

        RootRoute ->
            "/topics"

        ViewTopicRoute name partitionOffsets ->
            "/topic/" ++ name ++ getTopicOffsetUrl partitionOffsets


partitionOffsetUrlParser : Q.Parser PartitionOffsets
partitionOffsetUrlParser =
    Q.custom "offsets" listToPartitionOffset


listToPartitionOffset : List String -> PartitionOffsets
listToPartitionOffset list =
    List.foldl foldOffset
        Dict.empty
        list


getTopicOffsetUrl : PartitionOffsets -> String
getTopicOffsetUrl offsets =
    Dict.foldl
        (\a b str -> str ++ "offsets=" ++ String.fromInt a ++ ";" ++ String.fromInt b ++ "&")
        "?"
        offsets



-- TODO: Can this be done nicer?


foldOffset : String -> PartitionOffsets -> PartitionOffsets
foldOffset str dict =
    case String.split ";" str of
        [ partition, offsets ] ->
            case ( String.toInt partition, String.toInt offsets ) of
                ( Just p, Just o ) ->
                    Dict.insert p o dict

                _ ->
                    dict

        _ ->
            dict


getViewTopicPath : String -> String
getViewTopicPath name =
    getPath (ViewTopicRoute name Dict.empty)


browseTopic : String -> PartitionOffsets -> String
browseTopic name partitionOffsets =
    getPath (ViewTopicRoute name partitionOffsets)


getTopicOverViewPath : String
getTopicOverViewPath =
    getPath TopicsRoute


sendMessageRoute : String -> Int -> String
sendMessageRoute name partition =
    getPath (SendMessageRoute name partition)
