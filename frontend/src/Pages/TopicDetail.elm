port module Pages.TopicDetail exposing (Model, Msg(..), update, view)

import Browser.Navigation exposing (pushUrl, reload)
import Dict
import Element
import Element.Background
import Element.Events
import Element.Font
import Html exposing (Html)
import Html.Attributes
import Http exposing (emptyBody)
import JsonTree
import RemoteData exposing (RemoteData(..))
import Routes exposing (Route(..), browseTopic, getPath, sendMessageRoute)
import Set exposing (Set)
import Shared exposing (Config, getDangerousLinkStyle, getLinkStyle, viewHttpError)
import Topic exposing (PartitionDetail, Topic, TopicDetail, TopicMessage, addToOffsets)
import Url.Builder exposing (absolute, relative)


port copy : String -> Cmd msg


type alias Model =
    { topicDetailResponse : RemoteData Http.Error TopicDetail, messagesInJsonViewer : Set ( Int, Int ) }


type Msg
    = TopicDetailResponse (RemoteData Http.Error TopicDetail)
    | Copy String
    | DeleteTopic String
    | TopicDeleted (Result Http.Error ())
    | ResetTopic String
    | TopicReset (Result Http.Error ())
    | ToggleJsonView Int Int
    | Noop


update : Config -> Msg -> Model -> ( Model, Cmd Msg )
update config msg model =
    case msg of
        Copy message ->
            ( model, copy message )

        TopicDetailResponse topicDetailResponse ->
            let
                newModel =
                    { model | topicDetailResponse = topicDetailResponse }
            in
            ( newModel
            , Cmd.none
            )

        ToggleJsonView partition offset ->
            let
                key =
                    ( partition, offset )

                isKeyInSet =
                    Set.member key model.messagesInJsonViewer

                newSet =
                    if isKeyInSet then
                        Set.remove key model.messagesInJsonViewer

                    else
                        Set.insert key model.messagesInJsonViewer

                newModel =
                    { model | messagesInJsonViewer = newSet }
            in
            ( newModel, Cmd.none )

        DeleteTopic topicName ->
            ( model, deleteTopic config.apiUrl topicName )

        ResetTopic topicName ->
            ( model, resetTopic config.apiUrl topicName )

        TopicDeleted _ ->
            ( model, pushUrl config.key (relative [ getPath TopicsRoute ] []) )

        TopicReset _ ->
            ( model, reload )

        Noop ->
            ( model, Cmd.none )


view : Model -> Element.Element Msg
view model =
    let
        body =
            case model.topicDetailResponse of
                Success topicDetail ->
                    viewTopicDetail topicDetail model.messagesInJsonViewer

                Failure e ->
                    viewHttpError e

                _ ->
                    Element.text "Loading..."

        topicName =
            RemoteData.unwrap "..." .name model.topicDetailResponse
    in
    Element.column [ Element.width (Element.fill |> Element.maximum 1600) ]
        [ Element.row
            [ Element.paddingEach
                { top = 100
                , bottom = 16
                , left = 0
                , right = 0
                }
            , Element.centerX
            , Element.centerY
            , Element.spacingXY 24 0
            ]
            [ Element.el [ Element.Font.size 62 ] (Element.text topicName)
            , Element.el
                (getDangerousLinkStyle
                    ++ [ Element.pointer
                       , Element.Events.onClick (DeleteTopic topicName)
                       ]
                )
                (Element.text "Delete")
            , Element.el
                (getDangerousLinkStyle
                    ++ [ Element.pointer
                       , Element.Events.onClick (ResetTopic topicName)
                       ]
                )
                (Element.text "Reset")
            ]
        , Element.row [ Element.width Element.fill ] [ body ]
        ]


resetTopic : String -> String -> Cmd Msg
resetTopic apiUrl topicName =
    let
        url =
            apiUrl ++ "/api/v2/topic/" ++ topicName ++ "/reset"
    in
    Http.request
        { method = "DELETE"
        , url = url
        , body = emptyBody
        , tracker = Nothing
        , timeout = Nothing
        , headers = []
        , expect = Http.expectWhatever TopicReset
        }


deleteTopic : String -> String -> Cmd Msg
deleteTopic apiUrl topicName =
    let
        url =
            apiUrl ++ "/api/v2/topic/" ++ topicName ++ ""
    in
    Http.request
        { method = "DELETE"
        , url = url
        , body = emptyBody
        , tracker = Nothing
        , timeout = Nothing
        , headers = []
        , expect = Http.expectWhatever TopicDeleted
        }


viewTopicDetail : TopicDetail -> Set ( Int, Int ) -> Element.Element Msg
viewTopicDetail topicDetail messagesInJson =
    let
        olderLink =
            browseTopic topicDetail.name topicDetail.partitionOffsets

        newerLink =
            browseTopic topicDetail.name (addToOffsets 20 topicDetail.partitionOffsets)

        sendMessageLink =
            \partition -> sendMessageRoute topicDetail.name partition
    in
    Element.column
        [ Element.width Element.fill, Element.spacingXY 0 32 ]
        (List.map (viewPartitionDetail olderLink newerLink messagesInJson sendMessageLink) topicDetail.partitionDetails)


viewTopicDetailTableHeader : String -> String -> (Int -> String) -> PartitionDetail -> Element.Element Msg
viewTopicDetailTableHeader olderLink newerLink sendMessageLink partitionDetail =
    Element.row [ Element.width Element.fill ]
        [ Element.column [ Element.spacingXY 0 16 ]
            [ Element.row []
                [ Element.el [] (Element.text ("Partititon [" ++ String.fromInt partitionDetail.id ++ "]"))
                ]
            , Element.row []
                [ Element.el [] (Element.text ("High watermark offset [" ++ String.fromInt partitionDetail.highwatermarkOffset ++ "]"))
                ]
            , Element.row []
                [ Element.link getLinkStyle { label = Element.text "Send message on to this topic and partition", url = sendMessageLink partitionDetail.id }
                ]
            ]
        , Element.column [ Element.width Element.fill ]
            [ Element.row [ Element.alignRight ]
                [ Element.link getLinkStyle { label = Element.text "newer", url = newerLink }
                , Element.el [] (Element.text "/")
                , Element.link getLinkStyle { label = Element.text "older", url = olderLink }
                ]
            ]
        ]


viewTopicDetailTableBody : PartitionDetail -> Set ( Int, Int ) -> Element.Element Msg
viewTopicDetailTableBody partitionDetail messagesInJson =
    Element.wrappedRow [ Element.width Element.fill ]
        [ Element.indexedTable [ Element.Font.alignLeft ]
            { data = partitionDetail.messages
            , columns =
                [ { header = Element.el [ Element.paddingXY 24 12 ] (Element.text "Offset")
                  , width = Element.px 150
                  , view = viewTableOffset
                  }
                , { header = Element.el [ Element.paddingXY 24 12 ] (Element.text "Message")
                  , width = Element.fill
                  , view = viewTableMessage messagesInJson
                  }
                , { header = Element.el [ Element.paddingXY 24 12 ] (Element.text "Actions")
                  , width = Element.px 220
                  , view = viewTableActions
                  }
                ]
            }
        ]


getTableBackground : Int -> Element.Color
getTableBackground index =
    if modBy 2 index == 0 then
        Element.rgb 0.94 0.94 0.94

    else
        Element.rgb 1 1 1


viewTableMessage : Set ( Int, Int ) -> Int -> TopicMessage -> Element.Element Msg
viewTableMessage messagesInJson index message =
    let
        bodyPlainText =
            Element.text message.json

        bodyJsonViewer =
            Element.html <| viewJsonMessage message.json

        thisMessageInJson =
            Set.member ( message.partition, message.offset ) messagesInJson

        body =
            if thisMessageInJson then
                bodyJsonViewer

            else
                bodyPlainText
    in
    Element.paragraph
        [ Element.paddingXY 24 12
        , Element.Background.color (getTableBackground index)
        , Element.width (Element.fill |> Element.maximum 1230)
        , Element.clipX
        ]
        [ body ]


jsonTreeConfig =
    { onSelect = Nothing, toMsg = always Noop, colors = JsonTree.defaultColors }


viewJsonMessage : String -> Html Msg
viewJsonMessage json =
    JsonTree.parseString json
        |> Result.map (\tree -> JsonTree.view tree jsonTreeConfig JsonTree.defaultState)
        |> Result.withDefault (Html.div [ Html.Attributes.class "break-word" ] [ Html.text ("Failed to parse JSON: " ++ json) ])


viewTableActions : Int -> TopicMessage -> Element.Element Msg
viewTableActions index message =
    Element.paragraph
        [ Element.paddingXY 24 12
        , Element.Background.color (getTableBackground index)
        , Element.height Element.fill
        ]
        [ Element.row
            ([]
                ++ getLinkStyle
            )
            [ Element.el
                [ Element.pointer
                , Element.Events.onClick (Copy message.json)
                ]
                (Element.text "Copy")
            , Element.text " / "
            , Element.el
                [ Element.pointer
                , Element.Events.onClick (ToggleJsonView message.partition message.offset)
                ]
                (Element.text "Inspect")
            ]
        ]


viewTableOffset : Int -> TopicMessage -> Element.Element Msg
viewTableOffset index message =
    Element.el
        [ Element.paddingXY 24 12
        , Element.Background.color (getTableBackground index)
        , Element.height Element.fill
        ]
        (Element.text (String.fromInt message.offset))


viewPartitionDetail : String -> String -> Set ( Int, Int ) -> (Int -> String) -> PartitionDetail -> Element.Element Msg
viewPartitionDetail olderLink newerLink messagesInJson sendMessageLink partitionDetail =
    Element.column [ Element.spacingXY 0 24, Element.width Element.fill ]
        [ viewTopicDetailTableHeader olderLink newerLink sendMessageLink partitionDetail
        , viewTopicDetailTableBody partitionDetail messagesInJson
        ]
