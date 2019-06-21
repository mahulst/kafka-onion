port module Pages.TopicDetail exposing (Model, Msg(..), view, update)

import Dict
import Element
import Element.Background
import Element.Events
import Element.Font
import Http
import RemoteData exposing (RemoteData(..))
import Routes exposing (browseTopic, sendMessageRoute)
import Shared exposing (Flags, getLinkStyle, viewHttpError)
import Topic exposing (PartitionDetail, Topic, TopicDetail, TopicMessage, addToOffsets)


port copy : String -> Cmd msg


type alias Model =
    { topicDetailResponse : RemoteData Http.Error TopicDetail }


type Msg
    = TopicDetailLoaded (RemoteData Http.Error TopicDetail)
    | TopicDetailResponse (RemoteData Http.Error TopicDetail)
    | Copy String


update : Flags -> Msg -> Model -> ( Model, Cmd Msg )
update flags msg model =
    case msg of
        Copy message ->
            ( model, copy message )

        TopicDetailLoaded topicDetailResponse ->
            let
                newModel =
                    { topicDetailResponse = topicDetailResponse }
            in
            ( newModel
            , Cmd.none
            )
        TopicDetailResponse topicDetailResponse ->
            let
                newModel =
                    { topicDetailResponse = topicDetailResponse }
            in
            ( newModel
            , Cmd.none
            )


view : Model -> Element.Element Msg
view model =
    let
        topicDetail =
            case model.topicDetailResponse of
                Success e ->
                    e

                _ ->
                    TopicDetail "..." Dict.empty []

        topicName =
            topicDetail.name

        body =
            viewTopicDetail topicDetail
    in
    Element.column [ Element.width (Element.fill |> Element.maximum 1600), Element.explain Debug.todo ]
        [ Element.row
            [ Element.paddingEach
                { top = 100
                , bottom = 16
                , left = 0
                , right = 0
                }
            , Element.centerX
            , Element.centerY
            ]
            [ Element.el [ Element.Font.size 62 ] (Element.text topicName) ]
        , Element.row [ Element.width Element.fill ] [ body ]
        ]


viewTopicDetail : TopicDetail -> Element.Element Msg
viewTopicDetail topicDetail =
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
        (List.map (viewPartitionDetail olderLink newerLink sendMessageLink) topicDetail.partitionDetails)


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


viewTopicDetailTableBody : PartitionDetail -> Element.Element Msg
viewTopicDetailTableBody partitionDetail =
    Element.row [Element.width Element.fill]
        [ Element.indexedTable [ Element.Font.alignLeft ]
            { data = partitionDetail.messages
            , columns =
                [ { header = Element.el [ Element.paddingXY 24 12 ] (Element.text "Offset")
                  , width = Element.px 150
                  , view = viewTableOffset
                  }
                , { header = Element.el [ Element.paddingXY 24 12 ] (Element.text "Message")
                  , width = Element.fill
                  , view = viewTableMessage
                  }
                , { header = Element.el [ Element.paddingXY 24 12 ] (Element.text "Actions")
                  , width = Element.px 120
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


viewTableMessage : Int -> TopicMessage -> Element.Element Msg
viewTableMessage index message =
    Element.paragraph
        [ Element.paddingXY 24 12
        , Element.Background.color (getTableBackground index)
        , Element.height Element.fill
        ]
        [ Element.text message.json ]


viewTableActions : Int -> TopicMessage -> Element.Element Msg
viewTableActions index message =
    Element.paragraph
        [ Element.paddingXY 24 12
        , Element.Background.color (getTableBackground index)
        , Element.height Element.fill
        , Element.Events.onClick (Copy message.json)
        ]
        [ Element.el ([ Element.pointer ] ++ getLinkStyle) (Element.text "Copy") ]


viewTableOffset : Int -> TopicMessage -> Element.Element Msg
viewTableOffset index message =
    Element.el
        [ Element.paddingXY 24 12
        , Element.Background.color (getTableBackground index)
        , Element.height Element.fill
        ]
        (Element.text (String.fromInt message.offset))


viewPartitionDetail : String -> String -> (Int -> String) -> PartitionDetail -> Element.Element Msg
viewPartitionDetail olderLink newerLink sendMessageLink partitionDetail =
    Element.column [ Element.spacingXY 0 24, Element.width Element.fill ]
        [ viewTopicDetailTableHeader olderLink newerLink sendMessageLink partitionDetail
        , viewTopicDetailTableBody partitionDetail
        ]
