module Shared exposing (Config, Flags, getDangerousLinkStyle, getLinkStyle, viewHttpError)

import Browser.Navigation exposing (Key)
import Element
import Element.Background
import Element.Font
import Http


type alias Flags =
    { apiUrl : String }


type alias Config =
    { apiUrl : String
    , key : Key
    }


viewHttpError : Http.Error -> Element.Element msg
viewHttpError error =
    let
        message =
            case error of
                Http.BadUrl str ->
                    [ Element.paragraph [] [ Element.el [] (Element.text "Something is wrong with the url:") ]
                    , Element.paragraph [] [ Element.el [] (Element.text str) ]
                    ]

                Http.Timeout ->
                    [ Element.paragraph [] [ Element.el [] (Element.text "Request timed out!") ] ]

                Http.NetworkError ->
                    [ Element.paragraph [] [ Element.el [] (Element.text "Network error!") ] ]

                Http.BadStatus status ->
                    [ Element.paragraph [] [ Element.el [] (Element.text ("Got status code [" ++ String.fromInt status ++ "]")) ] ]

                Http.BadBody body ->
                    [ Element.paragraph [] [ Element.el [] (Element.text "Got unexpected body:") ]
                    , Element.paragraph [] [ Element.el [] (Element.text body) ]
                    ]
    in
    Element.column [ Element.width Element.fill, Element.Background.color red, Element.padding 24 ]
        [ Element.el
            []
            (Element.textColumn [ Element.width Element.fill ] message)
        ]


red =
    Element.rgb 0.7 0.4 0.4


blue =
    Element.rgb 0.06 0.5 0.8


getLinkStyle =
    [ Element.Font.bold, Element.Font.color blue ]


getDangerousLinkStyle =
    [ Element.Font.bold, Element.Font.color red ]
